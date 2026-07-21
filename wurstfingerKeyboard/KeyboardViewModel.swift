//
//  KeyboardViewModel.swift
//  Wurstfinger
//
//  Created by Claas Flint on 24.10.25.
//

import Combine
import CoreGraphics
import Foundation
import UIKit

enum KeyboardHapticEvent {
    case tap
    case drag
}

struct DeviceLayoutUtils {
    /// Returns screen bounds for layout calculations.
    /// UIScreen.main is deprecated in iOS 16+ but UIApplication.shared is unavailable in app extensions,
    /// so UIScreen.main remains the pragmatic choice for keyboard extensions.
    static var screenBounds: CGRect {
        UIScreen.main.bounds
    }

    /// Calculates the default keyboard scale to achieve a target width of ~270pt
    /// (which corresponds to ~67% of an iPhone 17 Pro width).
    static var defaultKeyboardScale: Double {
        let targetWidth: CGFloat = 270.0
        let screenWidth = screenBounds.width

        // Avoid division by zero
        guard screenWidth > 0 else { return 1.0 }

        // Calculate scale required to hit target width
        let calculatedScale = targetWidth / screenWidth

        // Clamp between reasonable min/max (e.g., 0.26 to 1.0)
        // 0.26 is roughly iPad width (1024pt) -> 270/1024 = 0.26
        return min(1.0, max(0.25, calculatedScale))
    }

    static let defaultKeyAspectRatio: Double = 1.0
    static let defaultKeyboardPosition: Double = 0.5
}

final class KeyboardViewModel: ObservableObject {
    // MARK: - Settings Keys (kept for backward compatibility)

    static let hapticTapIntensityKey = SettingsKey.hapticIntensityTap.rawValue
    static let hapticDragIntensityKey = SettingsKey.hapticIntensityDrag.rawValue
    static let numpadStyleKey = SettingsKey.numpadStyle.rawValue
    static let defaultTapIntensity: CGFloat = HapticSettings.defaultTapIntensity
    static let defaultDragIntensity: CGFloat = HapticSettings.defaultDragIntensity

    // MARK: - State

    /// Current width of the keyboard's containing view.
    /// Updated by the controller in `viewWillLayoutSubviews()` so that
    /// SwiftUI re-evaluates layout after orientation changes.
    @Published private(set) var viewWidth: CGFloat = UIScreen.main.bounds.width
    /// Whether the device is currently in a landscape orientation.
    /// Driven by the controller via `updateOrientation(isLandscape:)`, since
    /// the keyboard's own bounds are always shorter than tall and cannot
    /// reliably distinguish portrait from landscape on their own.
    @Published private(set) var isLandscape: Bool = false
    /// The currently active keyboard mode.
    @Published var currentMode: KeyboardMode?
    /// Name of the currently active mode in the data-driven definition.
    @Published var activeModeName: String = ModeNames.main
    @Published var spellcheckState: SpellcheckState = .idle

    // MARK: - Data-Driven Pipeline State (internal for extension access)

    var currentDefinition: KeyboardDefinition?
    var resolverChain: GestureResolverChain?
    var returnSwipeResolverChain: GestureResolverChain?
    var pipeline: ActionPipeline?
    weak var textInputTarget: TextInputTarget?
    var onAdvanceToNextInputMode: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?
    /// Locale used by the pipeline (set from the keyboard definition).
    var pipelineLocale: Locale?
    private var enabledLanguageIds: [String] = []

    // MARK: - Settings (delegated to extracted classes)

    let hapticSettings: HapticSettings
    let layoutSettings: LayoutSettings
    private let hapticManager: HapticFeedbackManager

    // MARK: - Computed Properties for Backward Compatibility

    var hapticIntensityTap: CGFloat {
        get { hapticSettings.tapIntensity }
        set { hapticSettings.tapIntensity = newValue }
    }

    var hapticIntensityDrag: CGFloat {
        get { hapticSettings.dragIntensity }
        set { hapticSettings.dragIntensity = newValue }
    }

    var hapticEnabled: Bool {
        get { hapticSettings.enabled }
        set { hapticSettings.enabled = newValue }
    }

    var utilityColumnLeading: Bool {
        get { layoutSettings.utilityColumnLeading }
        set { layoutSettings.utilityColumnLeading = newValue }
    }

    var keyAspectRatio: Double {
        get { layoutSettings.keyAspectRatio }
        set { layoutSettings.keyAspectRatio = newValue }
    }

    var keyboardScale: Double {
        get { layoutSettings.keyboardScale }
        set { layoutSettings.keyboardScale = newValue }
    }

    var keyboardHorizontalPosition: Double {
        get { layoutSettings.keyboardHorizontalPosition }
        set { layoutSettings.keyboardHorizontalPosition = newValue }
    }

    // MARK: - Private State

    let sharedDefaults: UserDefaults
    let shouldPersistSettings: Bool
    var isSpaceDragging = false
    var spaceDragResidual: CGFloat = 0
    /// Peak signed displacement during the current space drag. Used by the
    /// discrete cursor-movement mode to classify regular vs. return swipes.
    var spaceDragPeak: CGFloat = 0
    /// Cursor-movement style captured at the start of the current space drag, so
    /// a mid-drag settings change cannot switch classification mode mid-gesture.
    var spaceDragCursorStyle: CursorMovementStyle = .continuous
    var isDeleteDragging = false
    var deleteDragResidual: CGFloat = 0
    private var userDefaultsObserver: NSObjectProtocol?
    private var settingsCancellables = Set<AnyCancellable>()
    let wordChecker: WordChecking = AppleWordChecker()
    var spellcheckRefreshPending = false

    init(
        userDefaults: UserDefaults? = nil,
        shouldPersistSettings: Bool = true
    ) {
        // Initialize UserDefaults once
        let defaults = userDefaults ?? SharedDefaults.store
        sharedDefaults = defaults
        self.shouldPersistSettings = shouldPersistSettings

        // Initialize extracted settings classes
        hapticSettings = HapticSettings(defaults: defaults, shouldPersist: shouldPersistSettings)
        layoutSettings = LayoutSettings(defaults: defaults, shouldPersist: shouldPersistSettings)
        hapticManager = HapticFeedbackManager(settings: hapticSettings)

        enabledLanguageIds = LanguageSettings.loadEnabledLanguageIds(from: defaults)
            ?? [SharedDefaults.store.string(forKey: SettingsKey.selectedLanguageId.rawValue) ?? "en_US"]

        // Forward settings changes to trigger objectWillChange on this ViewModel
        hapticSettings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &settingsCancellables)
        layoutSettings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &settingsCancellables)

        // Observe in-process UserDefaults changes (e.g. utility column toggle).
        // Note: didChangeNotification only fires within the same process.
        // Cross-process updates from the host app are handled by
        // KeyboardViewController.viewWillAppear → reloadSettings().
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: sharedDefaults,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSettings()
        }
    }

    deinit {
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Updates the tracked view width. Called by the controller in
    /// `viewWillLayoutSubviews()` so SwiftUI re-renders after orientation changes.
    func updateViewWidth(_ width: CGFloat) {
        guard width != viewWidth else { return }
        viewWidth = width
    }

    /// Updates the tracked orientation. Called by the controller from
    /// `viewWillLayoutSubviews()` (which inspects its `traitCollection`) so
    /// `currentContext` can pick portrait/landscape arrangements correctly.
    func updateOrientation(isLandscape: Bool) {
        guard isLandscape != self.isLandscape else { return }
        self.isLandscape = isLandscape
    }

    // MARK: - Arrangement Selection

    /// Determines the active arrangement context based on orientation and
    /// the user's utility-column preference.
    var currentContext: ArrangementContext {
        let utilityLeft = layoutSettings.utilityColumnLeading
        switch (isLandscape, utilityLeft) {
        case (false, false): return .portrait
        case (false, true): return .portraitUtilityLeft
        case (true, false): return .landscape
        case (true, true): return .landscapeUtilityLeft
        }
    }

    /// The grid arrangement for `currentMode` and `currentContext`.
    /// Returns `nil` if no definition is loaded.
    var currentArrangement: GridArrangement? {
        currentMode?.arrangement(for: currentContext)
    }

    /// The active mode resolved from the current definition and mode name.
    var activeModeFromDefinition: KeyboardMode? {
        currentDefinition?.mode(activeModeName)
    }

    /// Exposes haptic tap to the pipeline extension.
    func triggerHapticTap() {
        hapticManager.tap()
    }

    func reloadSettings() {
        // Delegate to extracted settings classes - eliminates duplicate code
        hapticSettings.reload()
        layoutSettings.reload()

        enabledLanguageIds = LanguageSettings.loadEnabledLanguageIds(from: sharedDefaults)
            ?? enabledLanguageIds
    }

    func switchToNextLanguage() {
        // Always re-read the enabled list straight from shared defaults so a
        // stale in-memory copy (e.g. after the host app changed it) can't make
        // this a silent no-op.
        let stored = LanguageSettings.loadEnabledLanguageIds(from: sharedDefaults) ?? []
        let validStored = stored.filter { KeyboardRegistry.load(id: $0) != nil }

        // Fallback: if the enabled list isn't usable (empty, single entry, or
        // failed to sync from the app), cycle through *all* installed layouts
        // so the globe swipe always advances.
        let cycle = validStored.count > 1
            ? validStored
            : KeyboardRegistry.available.map { $0.id }

        enabledLanguageIds = cycle

        guard cycle.count > 1 else { return }

        let currentId = sharedDefaults.string(forKey: SettingsKey.selectedLanguageId.rawValue)
            ?? currentDefinition?.id
            ?? cycle.first
            ?? "en_US"
        let nextId = LanguageSettings.nextLanguageId(after: currentId, in: cycle)

        if nextId != currentId {
            sharedDefaults.set(nextId, forKey: SettingsKey.selectedLanguageId.rawValue)
            loadDefinition(for: nextId)
        }
    }

    var hasMultipleLanguages: Bool {
        enabledLanguageIds.count > 1
    }

    // MARK: - Emoji Panel

    /// Whether the scrollable emoji panel is currently shown instead of the grid.
    @Published var emojiActive: Bool = false

    /// Show the emoji panel.
    func openEmoji() {
        emojiActive = true
    }

    /// Dismiss the emoji panel and return to the alphabetic layer.
    func closeEmoji() {
        emojiActive = false
        switchToMode(ModeNames.main)
    }

    /// Insert an emoji directly into the document.
    func insertEmoji(_ emoji: String) {
        dispatchAction(.commitText(emoji))
        feedbackTap()
    }

    /// Backspace from within the emoji panel.
    func emojiDeleteBackward() {
        dispatchAction(.deleteBackward)
        feedbackTap()
    }

    var currentLanguageLabel: String {
        let lang = pipelineLocale?.language.languageCode?.identifier ?? ""
        return lang.uppercased()
    }

    // MARK: - Haptic Feedback (delegated to HapticFeedbackManager)

    /// Haptic feedback for key touch-down — called by button views on first contact
    func feedbackTap() {
        hapticManager.tap()
    }

    func feedbackDrag() {
        hapticManager.drag()
    }
}
