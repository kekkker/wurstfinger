//
//  KeyboardViewModel+Pipeline.swift
//  Wurstfinger
//
//  Extension that handles the data-driven gesture pipeline:
//  definition loading, pipeline assembly, gesture resolution
//  (Thumb-Key semantics), mode switching, and slide handling.
//

import Foundation
import QuartzCore

extension KeyboardViewModel {
    // MARK: - Data-Driven Loading & Pipeline

    /// Loads a keyboard definition by ID from the registry and sets up the
    /// action pipeline.
    func loadDefinition(for id: String) {
        guard let base = KeyboardRegistry.load(id: id) else { return }
        let definition = applyLoadTimeSettings(to: base)
        currentDefinition = definition
        activeModeName = definition.defaultMode
        pipelineLocale = definition.locale
        currentMode = definition.mode(activeModeName)
        rebuildPipeline()
    }

    /// Applies settings that shape the definition itself. The registry caches
    /// the canonical definition, so this always derives a copy.
    private func applyLoadTimeSettings(to definition: KeyboardDefinition) -> KeyboardDefinition {
        var result = definition

        // Classic (7-8-9) numpad ordering.
        let raw = sharedDefaults.string(forKey: SettingsKey.numpadStyle.rawValue)
        if raw.flatMap(NumpadStyle.init(rawValue:)) == .classic {
            let label = definition.numericBackToAlphaLabel
            let classicNumeric = definition.settings.numericLayout == .thumbKey
                ? NumericLayouts.thumbKey(backToAlphaLabel: label, classicOrder: true)
                : NumericLayouts.classic(backToAlphaLabel: label)
            result = result.replacingMode(ModeNames.numeric, with: classicNumeric)
        }

        // The user's key modifications. A broken config leaves the layout
        // unchanged; the settings screen shows the error.
        let modifications = sharedDefaults.string(forKey: SettingsKey.keyModifications.rawValue) ?? ""
        if let modified = try? KeyModifications.apply(modifications, to: result) {
            result = modified
        }

        // Thumb-Key's "switch to letters after space" on the number layer.
        if behaviorSettings.switchToLettersAfterSpace, let numeric = result.mode(ModeNames.numeric) {
            result = result.replacingMode(
                ModeNames.numeric,
                with: numeric.with(autoTransitions: [.whitespace: ModeNames.main])
            )
        }
        return result
    }

    /// Injects the text input target (typically a `DocumentProxyTarget`).
    func bindTextInputTarget(_ target: TextInputTarget) {
        textInputTarget = target
        rebuildPipeline()
        scheduleSpellcheckRefresh()
    }

    /// Injects VC-specific action closures (keyboard switch, dismiss, settings).
    func bindViewControllerActions(
        advanceToNextInputMode: @escaping () -> Void,
        dismissKeyboard: @escaping () -> Void,
        openSettings: @escaping () -> Void = {}
    ) {
        onAdvanceToNextInputMode = advanceToNextInputMode
        onDismissKeyboard = dismissKeyboard
        onOpenSettings = openSettings
        rebuildPipeline()
    }

    /// Assembles the full action pipeline with all middlewares.
    func rebuildPipeline() {
        guard let definition = currentDefinition else {
            pipeline = nil
            return
        }
        var middlewares: [ActionMiddleware] = []

        // 1. Compose + Cycle Accents
        middlewares.append(ComposeMiddleware(
            compose: { previous, trigger in
                ComposeEngine.compose(previous: previous, trigger: trigger)
            },
            cycleAccent: { character in
                ComposeEngine.cycleAccent(for: character)
            },
            previousCharacter: { [weak self] in
                self?.textInputTarget?.documentContextBeforeInput?.last.map(String.init) ?? ""
            },
            deletePreviousCharacter: { [weak self] in
                self?.textInputTarget?.deleteBackward()
            }
        ))

        // 2. Telex (only active for Telex languages)
        let inputMethod = definition.settings.inputMethod
        middlewares.append(TelexMiddleware(
            isActive: { inputMethod == .telex },
            documentContextBefore: { [weak self] in
                self?.textInputTarget?.documentContextBeforeInput
            },
            deleteBackward: { [weak self] in
                self?.textInputTarget?.deleteBackward()
            },
            composeDigraph: { prev2, prev1, trigger in
                ComposeEngine.composeTelexDigraph(prev2: prev2, prev1: prev1, trigger: trigger)
            },
            composeSingle: { previous, trigger in
                ComposeEngine.composeTelex(previous: previous, trigger: trigger)
            }
        ))

        // 3. Advanced text (words, lines, capitalization, clipboard, bridge)
        middlewares.append(AdvancedTextMiddleware(
            target: { [weak self] in self?.textInputTarget },
            locale: { [weak self] in self?.pipelineLocale ?? Locale.current },
            bridge: { [weak self] in self?.textCommandBridge },
            clipboard: { [weak self] in self?.clipboardHistory }
        ))

        // 4. Basic text input (commitText, deleteBackward, space, newline, moveCursor)
        middlewares.append(TextInputMiddleware(
            target: { [weak self] in self?.textInputTarget }
        ))

        // 5. View controller actions (keyboard switch, dismiss, settings)
        middlewares.append(ViewControllerActionMiddleware(
            onAdvanceToNextInputMode: { [weak self] in self?.onAdvanceToNextInputMode?() },
            onDismissKeyboard: { [weak self] in self?.onDismissKeyboard?() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() }
        ))

        // 6. Auto-capitalization and one-shot shift
        let autoCapitalizers = definition.settings.autoCapitalizers
        middlewares.append(AutoCapitalizationMiddleware(
            isEnabled: { [weak self] in
                guard let self else { return false }
                return behaviorSettings.autoCapitalize && definition.settings.autoCapitalize
            },
            applyAutoCapitalizers: { [weak self] in
                self?.applyAutoCapitalizers(autoCapitalizers)
            },
            shouldCapitalize: { [weak self] in
                self?.shouldAutoCapitalize() ?? false
            },
            setShifted: { [weak self] shifted in
                self?.applyAutoShift(shifted)
            }
        ))

        // 7. Mode transitions (auto-transitions from key category)
        middlewares.append(ModeTransitionMiddleware(
            definition: definition,
            onModeChange: { [weak self] newMode in
                self?.switchToMode(newMode)
            }
        ))

        pipeline = ActionPipeline(middlewares: middlewares)
    }

    // MARK: - Auto-Capitalization

    /// Whether the next character should be uppercase in the focused field.
    func shouldAutoCapitalize() -> Bool {
        guard let target = textInputTarget, target.fieldKind != .addressOrPassword else { return false }
        return AutoCapitalization.shouldCapitalize(
            context: target.documentContextBeforeInput,
            mode: target.capitalizationMode
        )
    }

    /// Runs the first matching language rule (e.g. " i " → " I ").
    private func applyAutoCapitalizers(_ rules: [AutoCapitalizerRule]) {
        guard let target = textInputTarget,
              let context = target.documentContextBeforeInput,
              let rule = rules.first(where: { context.hasSuffix($0.pattern) })
        else { return }
        for _ in 0 ..< rule.pattern.count {
            target.deleteBackward()
        }
        target.insertText(rule.replacement)
    }

    /// Shifts or unshifts after committed text. The number layer and caps
    /// lock are left alone.
    private func applyAutoShift(_ shifted: Bool) {
        guard activeModeName == ModeNames.main || activeModeName == ModeNames.shifted else { return }
        switchToMode(shifted ? ModeNames.shifted : ModeNames.main)
    }

    /// Picks the starting layer for a newly focused field, like Thumb-Key:
    /// numbers for number pads, shifted where the field wants a capital.
    func resetModeForCurrentField() {
        closePanels()
        guard let target = textInputTarget else { return }
        if target.fieldKind == .number {
            switchToMode(ModeNames.numeric)
        } else if behaviorSettings.autoCapitalize,
                  currentDefinition?.settings.autoCapitalize == true,
                  shouldAutoCapitalize() {
            switchToMode(ModeNames.shifted)
        } else {
            switchToMode(ModeNames.main)
        }
    }

    // MARK: - Gesture Dispatch

    /// Settings snapshot for a touch on `key`, sized for a key of
    /// `keySize` points (average of width and height).
    func gestureConfig(for key: KeyConfig, keySize: CGFloat, pixelScale: CGFloat) -> KeyGestureConfig {
        let settings = behaviorSettings
        let hasGhost = ghostMode(for: activeModeFromDefinition) != nil
        return KeyGestureConfig(
            swipeMode: key.swipeMode,
            directionMode: hasGhost ? .eightWay : key.swipeMode,
            slideType: key.slideType,
            minSwipeLength: CGFloat(settings.minSwipeLength),
            touchSlop: KeyboardConstants.Gesture.touchSlop * pixelScale,
            keySize: keySize * pixelScale,
            hasLongPress: key.bindings[.longPress] != nil,
            circularDragEnabled: settings.circularDragEnabled,
            slideEnabled: settings.slideEnabled,
            slideHoldEnabled: settings.slideHoldEnabled,
            spacebarDeadzone: settings.slideSpacebarDeadzone,
            backspaceDeadzone: settings.slideBackspaceDeadzone,
            cursorMode: settings.slideCursorMovementMode,
            slideSensitivity: settings.slideSensitivity
        )
    }

    /// Handles one gesture event from the key `keyId`. Returns the action it
    /// performed (for the key's press animation), if any.
    @discardableResult
    func handleKeyEvent(_ event: KeyGestureEvent, keyId: String) -> KeyAction? {
        guard let mode = activeModeFromDefinition, let key = mode.key(for: keyId) else { return nil }
        switch event {
        case .tap:
            return handleTap(on: key)
        case .longPress:
            guard let binding = key.bindings[.longPress] else { return nil }
            feedbackTap()
            perform(binding)
            return binding.action
        case let .drag(outcome):
            guard let binding = resolveDrag(outcome, key: key, in: mode) else { return nil }
            perform(binding)
            tapCounts[key.id] = 0
            lastTap = LastTap(
                action: binding.action, time: CACurrentMediaTime(),
                context: textInputTarget?.documentContextBeforeInput
            )
            return binding.action
        case .slideCursor, .selectionBegan, .selectionChanged, .selectionCollapsed, .deleteSelection, .slideHoldTick:
            handleSlideEvent(event, key: key)
            return nil
        }
    }

    /// Dispatches a plain gesture type, as the classifier would report it.
    /// Convenience for tests and previews.
    func handleGesture(_ gesture: GestureType, keyId: String, isReturn: Bool) {
        switch gesture {
        case .tap:
            handleKeyEvent(.tap, keyId: keyId)
        case .longPress:
            handleKeyEvent(.longPress, keyId: keyId)
        case .circularClockwise, .circularCounterclockwise:
            let direction: CircularDirection = gesture == .circularClockwise ? .clockwise : .counterclockwise
            handleKeyEvent(
                .drag(DragOutcome(finalDirection: nil, maxDirection: nil, isReturn: true, circular: direction)),
                keyId: keyId
            )
        default:
            handleKeyEvent(
                .drag(DragOutcome(finalDirection: gesture, maxDirection: gesture, isReturn: isReturn, circular: nil)),
                keyId: keyId
            )
        }
    }

    /// Handles the utility keys beside the emoji picker. Taps run the main
    /// layer's key (so 123 opens the number layer); swipes resolve on the
    /// active layer.
    func handleEmojiPanelKeyEvent(_ event: KeyGestureEvent, key: KeyConfig) -> KeyAction? {
        guard event == .tap, let tap = key.bindings[.tap] else {
            return handleKeyEvent(event, keyId: key.id)
        }
        perform(tap)
        return tap.action
    }

    // MARK: - Tap (Multi-Tap)

    /// A tap runs the key's tap action, or — when the same key is tapped
    /// again within a second and the cursor did not move — the next action in
    /// its tap cycle (Thumb-Key's `nextTapActions`).
    private func handleTap(on key: KeyConfig) -> KeyAction? {
        guard let tap = key.bindings[.tap] else { return nil }
        let time = CACurrentMediaTime()
        let context = textInputTarget?.documentContextBeforeInput

        var count = 0
        if let last = lastTap, time - last.time < 1, last.action == tap.action, last.context == context {
            count = (tapCounts[key.id] ?? 0) + 1
        }
        tapCounts[key.id] = count

        let cycle = behaviorSettings.spacebarMultiTaps ? [tap.action] + (key.tapCycleActions ?? []) : [tap.action]
        let action = cycle[count % cycle.count]
        let binding = action == tap.action
            ? tap
            : KeyBinding(label: tap.label, action: action, category: nil, returnAction: nil, accessibilityLabel: nil)
        perform(binding)
        lastTap = LastTap(action: tap.action, time: time, context: textInputTarget?.documentContextBeforeInput)
        return action
    }

    // MARK: - Drag Resolution

    /// Maps a finished drag to a binding, like Thumb-Key's `onDragEnd`:
    /// a returning drag tries the circle action, then the swipe's return
    /// action, the opposite-case swipe and the ghost key's return action; a
    /// plain swipe tries the key, then its ghost key. Anything unresolved
    /// types the key's tap action.
    private func resolveDrag(_ outcome: DragOutcome, key: KeyConfig, in mode: KeyboardMode) -> KeyBinding? {
        let ghost = ghostMode(for: mode)
        if outcome.isReturn {
            if let circular = outcome.circular, let binding = circularBinding(circular, key: key, in: mode) {
                return binding
            }
            if behaviorSettings.dragReturnEnabled, let direction = outcome.maxDirection {
                var resolvers: [GestureResolver] = [ReturnSwipeResolver()]
                if let opposite = oppositeCaseMode(for: mode) {
                    resolvers.append(OppositeCaseResolver(oppositeMode: opposite))
                }
                if let ghost {
                    resolvers.append(GhostKeyResolver(fallbackMode: ghost, usesReturnAction: true))
                }
                if let binding = GestureResolverChain(resolvers: resolvers).resolve(keyId: key.id, gesture: direction, in: mode) {
                    return binding
                }
            }
        } else if let direction = outcome.finalDirection {
            var resolvers: [GestureResolver] = [PrimaryResolver()]
            if let ghost {
                resolvers.append(GhostKeyResolver(fallbackMode: ghost))
            }
            if let binding = GestureResolverChain(resolvers: resolvers).resolve(keyId: key.id, gesture: direction, in: mode) {
                return binding
            }
        }
        return key.bindings[.tap]
    }

    /// An explicit circle binding (e.g. number-layer symbols), else the
    /// configured circle action: the opposite-case letter or the number key.
    private func circularBinding(_ direction: CircularDirection, key: KeyConfig, in mode: KeyboardMode) -> KeyBinding? {
        let gesture: GestureType = direction == .clockwise ? .circularClockwise : .circularCounterclockwise
        let opposite: GestureType = direction == .clockwise ? .circularCounterclockwise : .circularClockwise
        if let explicit = key.bindings[gesture] ?? key.bindings[opposite] {
            return explicit
        }
        let choice = direction == .clockwise
            ? behaviorSettings.clockwiseDragAction
            : behaviorSettings.counterclockwiseDragAction
        switch choice {
        case .oppositeCase:
            return oppositeCaseMode(for: mode)?.key(for: key.id)?.bindings[.tap]
        case .numeric:
            return letterLayerNumericMode(for: mode)?.key(for: key.id)?.bindings[.tap]
        }
    }

    /// The layer with the other letter case, for the letter layers.
    private func oppositeCaseMode(for mode: KeyboardMode) -> KeyboardMode? {
        switch mode.name {
        case ModeNames.main: currentDefinition?.mode(ModeNames.shifted)
        case ModeNames.shifted, ModeNames.capsLock: currentDefinition?.mode(ModeNames.main)
        default: nil
        }
    }

    /// The number layer behind the letter layers.
    private func letterLayerNumericMode(for mode: KeyboardMode) -> KeyboardMode? {
        guard [ModeNames.main, ModeNames.shifted, ModeNames.capsLock].contains(mode.name) else { return nil }
        return currentDefinition?.mode(ModeNames.numeric)
    }

    /// The number layer as ghost keys, when enabled.
    private func ghostMode(for mode: KeyboardMode?) -> KeyboardMode? {
        guard behaviorSettings.ghostKeysEnabled, let mode else { return nil }
        return letterLayerNumericMode(for: mode)
    }

    // MARK: - Actions

    /// Runs a binding: keyboard-state actions here, text actions through the pipeline.
    func perform(_ binding: KeyBinding) {
        switch binding.action {
        case let .switchMode(target):
            closePanels()
            switchToMode(target)
        case let .toggleShift(enable):
            switchToMode(enable ? ModeNames.shifted : ModeNames.main)
        case .toggleCapsLock:
            switchToMode(activeModeName == ModeNames.capsLock ? ModeNames.shifted : ModeNames.capsLock)
        case .switchToNextLanguage:
            switchToNextLanguage()
        case .openEmoji:
            openEmoji()
        case .openClipboardHistory:
            openClipboardHistory()
        case .toggleHideLetters:
            toggleHideLetters()
        case .cycleKeyboardPosition:
            cycleKeyboardPosition()
        default:
            processAndRefreshSpellcheck(ActionContext(action: binding.action, binding: binding, mode: activeModeName))
        }
    }

    /// Switches to a named mode, updating published state.
    func switchToMode(_ modeName: String) {
        guard modeName != activeModeName,
              let definition = currentDefinition,
              definition.mode(modeName) != nil
        else { return }
        activeModeName = modeName
        currentMode = definition.mode(modeName)
    }

    // MARK: - Slides

    private func handleSlideEvent(_ event: KeyGestureEvent, key: KeyConfig) {
        let bridge = textCommandBridge.flatMap { $0.isAvailable ? $0 : nil }
        switch event {
        case let .slideCursor(offset):
            dispatchAction(.moveCursor(offset: offset))
            feedbackDrag()
        case .selectionBegan:
            slideSelectionOffset = 0
            bridge?.send(.beginSelection)
        case let .selectionChanged(total):
            if let bridge {
                bridge.send(.extendSelection(total))
            } else if key.slideType == .delete {
                // Without selections, delete progressively instead.
                let change = total - slideSelectionOffset
                for _ in 0 ..< abs(change) {
                    dispatchAction(change < 0 ? .deleteBackward : .deleteForward)
                }
            }
            slideSelectionOffset = total
            feedbackDrag()
        case let .selectionCollapsed(toEnd):
            bridge?.send(.collapseSelection(toEnd: toEnd))
            slideSelectionOffset = 0
        case .deleteSelection:
            if bridge != nil, slideSelectionOffset != 0 {
                dispatchAction(.deleteBackward)
                feedbackDrag()
            }
            slideSelectionOffset = 0
        case let .slideHoldTick(direction, word):
            let forward = direction == .swipeRight
            switch key.slideType {
            case .moveCursor:
                dispatchAction(word
                    ? (forward ? .moveWordForward : .moveWordBackward)
                    : .moveCursor(offset: forward ? 1 : -1))
            case .delete:
                dispatchAction(word ? .deleteWordBackward : .deleteBackward)
            case .none:
                return
            }
            feedbackDrag()
        case .tap, .longPress, .drag:
            break
        }
    }

    // MARK: - Dispatch

    /// Dispatches a raw action through the pipeline (no binding context).
    func dispatchAction(_ action: KeyAction) {
        let context = ActionContext(action: action, binding: nil, mode: activeModeName)
        processAndRefreshSpellcheck(context)
    }

    private func processAndRefreshSpellcheck(_ context: ActionContext) {
        pipeline?.process(context)
        scheduleSpellcheckRefresh()
    }
}
