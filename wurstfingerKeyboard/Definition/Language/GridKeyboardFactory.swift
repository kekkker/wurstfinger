//
//  GridKeyboardFactory.swift
//  Wurstfinger
//
//  Factory for creating grid-based keyboard definitions.
//

import Foundation

/// Factory for creating complete grid-based keyboard definitions.
/// All shared structure (punctuation, utility keys, arrangements, shifted layer)
/// is generated automatically — only language-specific parameters are needed.
enum GridKeyboardFactory {
    /// Creates a complete keyboard definition from language-specific parameters.
    ///
    /// - Parameters:
    ///   - id: Unique keyboard identifier (e.g. "de_messagease")
    ///   - title: Display name (e.g. "Deutsch MessagEase")
    ///   - localeIdentifier: Locale string for uppercasing (e.g. "de_DE")
    ///   - centerCharacters: 3x3 grid of center tap characters
    ///   - directionalOverrides: Per-slot overrides that replace CommonKeys defaults
    ///   - numericBackToAlphaLabel: Label shown on the symbols key in numeric
    ///     mode that switches back to the main (alphabetic) layer. Defaults to
    ///     the Latin "abc"; non-Latin layouts (Hebrew, Russian, …) should
    ///     supply a script-appropriate label.
    ///   - inputMethod: Which input method is applied to committed characters.
    ///     Defaults to `.direct`; Vietnamese layouts should pass `.telex` so
    ///     that `TelexMiddleware` activates for this keyboard at runtime.
    ///   - cleanLetters: Thumb-Key style: drop the shared MessagEase
    ///     punctuation from letter keys (keeping shift), mute the remaining
    ///     punctuation legends, and use Thumb-Key's number layer.
    ///   - swipeModes: Per-slot direction zones (Thumb-Key's `swipeType`).
    ///     Slots not listed accept all 8 directions.
    ///   - autoCapitalizers: Language text rules applied after typing.
    static func layout(
        id: String,
        title: String,
        localeIdentifier: String,
        centerCharacters: [[String]],
        directionalOverrides: [String: [GestureType: String]] = [:],
        numericBackToAlphaLabel: String = NumericLayouts.defaultBackToAlphaLabel,
        inputMethod: InputMethodKind = .direct,
        cleanLetters: Bool = false,
        swipeModes: [String: SwipeMode] = [:],
        autoCapitalizers: [AutoCapitalizerRule] = []
    ) -> KeyboardDefinition {
        precondition(
            centerCharacters.count == 3 && centerCharacters.allSatisfy { $0.count == 3 },
            "centerCharacters must be a 3×3 matrix"
        )

        let locale = Locale(identifier: localeIdentifier)
        let arrangements = StandardArrangements.grid3x3

        // 1. Build 9 letter keys from center characters + shared defaults + overrides
        var letterKeys: [String: KeyConfig] = [:]
        for (rowIdx, row) in centerCharacters.enumerated() {
            for (colIdx, char) in row.enumerated() {
                let slotId = GridSlot.allSlots[rowIdx][colIdx]

                // Start with shared defaults for this slot. When the layout wants
                // clean letter keys (Thumb-Key style), drop the default
                // punctuation/symbols but keep modifier bindings (shift lives on
                // midRight) so the shift gestures still work.
                let slotDefaults = CommonKeys.defaultSlotBindings[slotId] ?? [:]
                var bindings = cleanLetters
                    ? slotDefaults.filter { $0.value.category == .modifier }
                    : slotDefaults

                // Apply language-specific overrides (replace default binding for that gesture).
                // Swipe-and-return on a letter types it in the opposite case
                // (resolved from the other layer), so no return action is needed.
                if let overrides = directionalOverrides[slotId] {
                    for (gesture, text) in overrides {
                        let isLetter = text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
                        bindings[gesture] = KeyBinding(
                            label: text, action: .commitText(text),
                            category: nil, returnAction: nil, accessibilityLabel: nil,
                            legend: cleanLetters && !isLetter ? .muted : nil
                        )
                    }
                }

                // Set the tap binding from center character
                bindings[.tap] = KeyBinding(
                    label: char, action: .commitText(char),
                    category: nil, returnAction: nil, accessibilityLabel: nil
                )

                letterKeys[slotId] = KeyConfig(
                    id: slotId, bindings: bindings, swipeMode: swipeModes[slotId] ?? .eightWay,
                    slideType: .none, style: .primary, tapCycleActions: nil
                )
            }
        }

        // 2. Merge utility keys
        let allKeys = letterKeys.merging(CommonKeys.allUtilityKeys) { letter, _ in letter }

        // 3. Main layer: ↑ shifts, ↓ unshifts (no legend).
        let mainMode = KeyboardMode(
            name: ModeNames.main,
            keys: allKeys,
            arrangements: arrangements,
            autoTransitions: [:],
            doubleTapMode: nil
        )

        // 4. Shifted and caps lock share the uppercased keys; ↑ toggles caps
        // lock (its legend changes while locked) and ↓ unshifts.
        let shiftedBase = mainMode.generateShifted(locale: locale)
            .replacingBinding(keyId: GridSlot.midRight, gesture: .swipeUp, with: CommonKeys.capsLockToggle)
            .replacingBinding(keyId: GridSlot.midRight, gesture: .swipeDown, with: CommonKeys.shiftDown)
        let capsLockMode = shiftedBase.with(name: ModeNames.capsLock)

        let numericMode = cleanLetters
            ? NumericLayouts.thumbKey(backToAlphaLabel: numericBackToAlphaLabel)
            : NumericLayouts.phone(backToAlphaLabel: numericBackToAlphaLabel)

        // 5. Assemble definition
        return KeyboardDefinition(
            title: title,
            id: id,
            localeIdentifier: localeIdentifier,
            modes: [
                ModeNames.main: mainMode,
                ModeNames.shifted: shiftedBase,
                ModeNames.capsLock: capsLockMode,
                ModeNames.numeric: numericMode,
            ],
            defaultMode: ModeNames.main,
            settings: KeyboardDefinitionSettings(
                autoCapitalize: true,
                autoCapitalizers: autoCapitalizers,
                composeRuleOverrides: nil,
                inputMethod: inputMethod,
                numericLayout: cleanLetters ? .thumbKey : .messagEase
            ),
            numericBackToAlphaLabel: numericBackToAlphaLabel
        )
    }
}
