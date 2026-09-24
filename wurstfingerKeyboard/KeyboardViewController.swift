//
//  KeyboardViewController.swift
//  Wurstfinger
//
//  Created by Claas Flint on 24.10.25.
//

import Foundation
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<AnyView>?
    private lazy var viewModel = KeyboardViewModel()
    private var heightConstraint: NSLayoutConstraint?
    private var documentProxyTarget: DocumentProxyTarget?

    /// Breathing room below the keys. Owned by the extension rather than left
    /// to the system's bottom inset: the band the system reserves is painted
    /// with its own gray backdrop, which a third-party keyboard cannot
    /// recolour. Reserving it here means the gap sits inside the keyboard's
    /// own view and takes the theme's background instead.
    private static let bottomContentGap: CGFloat = 20.0

    /// Signature of the definition currently loaded into the pipeline. Used to
    /// skip the pipeline rebuild on every `viewWillAppear` when nothing that
    /// affects the definition changed.
    private var loadedDefinitionSignature: String?

    /// The focused document, to pick a fresh starting layer when focus moves.
    private var currentDocumentIdentifier: UUID?

    /// Reports the active keyboard language to iOS (shown in Settings > Keyboards).
    /// Reads directly from SharedDefaults to pick up language changes made in the host app,
    /// since the LanguageSettings singleton may hold a stale value from its init.
    override var primaryLanguage: String? {
        get {
            resolvedLanguage.locale.identifier
        }
        set {
            super.primaryLanguage = newValue
        }
    }

    /// The active language, resolved identically for both `primaryLanguage`
    /// (reported to iOS) and definition loading. Reads the selected id, falls
    /// back to the detected system language, then to English for an unknown id —
    /// so the rendered layout and the locale shown by iOS never diverge.
    private var resolvedLanguage: LanguageConfig {
        let requestedId = SharedDefaults.store.string(
            forKey: SettingsKey.selectedLanguageId.rawValue
        ) ?? LanguageSettings.detectSystemLanguage()
        return LanguageConfig.language(withId: requestedId) ?? .english
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Opaque, not clear: the SwiftUI content is shorter than the region
        // iOS hands the extension, and a transparent root lets the system's
        // gray keyboard backdrop show through in the leftover band.
        applyBackgroundColor()

        // Completely disable the gray accessory bar
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        inputAssistantItem.allowsHidingShortcuts = true

        // Wire up the data-driven pipeline
        let target = DocumentProxyTarget(controller: self)
        documentProxyTarget = target
        viewModel.bindTextInputTarget(target)
        viewModel.textCommandBridge = DarwinTextCommandBridge()
        viewModel.bindViewControllerActions(
            advanceToNextInputMode: { [weak self] in self?.advanceToNextInputMode() },
            dismissKeyboard: { [weak self] in self?.dismissKeyboard() },
            openSettings: { [weak self] in self?.openContainingApp(path: "settings") }
        )

        // Load the keyboard definition for the selected language
        loadDefinitionIfNeeded()

        // Configure hosting synchronously so the SwiftUI view exists
        // before viewWillAppear sets the height constraint. Deferring via
        // DispatchQueue.main.async caused a race in WebView-based apps where
        // viewWillAppear ran before configureHosting, leaving the extension
        // with a height constraint but no content.
        configureHosting()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Persist Full Access status so the host app can show/hide haptic settings
        SharedDefaults.store.set(hasFullAccess, forKey: SettingsKey.keyboardFullAccess.rawValue)
        // Reload settings every time keyboard appears
        viewModel.reloadSettings()
        // Reload definition only if language (or numpad style) changed while the
        // keyboard was backgrounded — avoids rebuilding the pipeline every time.
        loadDefinitionIfNeeded()
        updateKeyboardHeight()
        viewModel.clipboardHistory.captureSystemPasteboard()
        currentDocumentIdentifier = textDocumentProxy.optionalDocumentIdentifier
        viewModel.resetModeForCurrentField()
    }

    /// Loads the keyboard definition only when the inputs that determine it
    /// (selected language, numpad style) have changed since the last load.
    private func loadDefinitionIfNeeded() {
        // Resolve via the shared helper so a stale/invalid persisted id falls
        // back the same way `primaryLanguage` does (system language, then
        // English) instead of leaving loadDefinition a no-op.
        let languageId = resolvedLanguage.id
        let numpadStyle = SharedDefaults.store.string(
            forKey: SettingsKey.numpadStyle.rawValue
        ) ?? ""
        let lettersAfterSpace = viewModel.behaviorSettings.switchToLettersAfterSpace
        let modifications = SharedDefaults.store.string(forKey: SettingsKey.keyModifications.rawValue) ?? ""
        let signature = "\(languageId)|\(numpadStyle)|\(lettersAfterSpace)|\(modifications)"
        guard signature != loadedDefinitionSignature else { return }
        // Cache the signature only after a successful load so a failed lookup
        // does not suppress future reload attempts.
        viewModel.loadDefinition(for: languageId)
        loadedDefinitionSignature = signature
    }

    private func updateKeyboardHeight() {
        // Keys scale, but SwiftUI's grid gaps and outer padding stay fixed.
        // Match that rendered geometry exactly so compact layouts are not
        // clipped at the top by an undersized keyboard host view.
        // Grow by the gap so reserving it does not squeeze the keys.
        let defaults = SharedDefaults.store
        let backdrop = defaults.bool(forKey: SettingsKey.backdropEnabled.rawValue)
            ? KeyboardConstants.Layout.backdropTopPadding : 0
        let bottomOffset = CGFloat(defaults.double(forKey: SettingsKey.bottomOffset.rawValue))
        let finalHeight = KeyboardConstants.Calculations.renderedHeight(
            aspectRatio: viewModel.keyAspectRatio,
            scale: viewModel.keyboardScale,
            rows: viewModel.currentArrangement?.rows.count ?? KeyboardConstants.KeyDimensions.totalRows
        ) + backdrop + bottomOffset + Self.bottomContentGap

        if let constraint = heightConstraint {
            if constraint.constant != finalHeight {
                constraint.constant = finalHeight
            }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: finalHeight)
            constraint.priority = .defaultHigh
            constraint.isActive = true
            heightConstraint = constraint
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyBackgroundColor()
        // Force hide the assistant view on every layout
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        // Update viewModel with current width so SwiftUI re-renders after
        // orientation changes that happen while the keyboard is backgrounded.
        viewModel.updateViewWidth(view.bounds.width)
        let isLandscape = detectIsLandscape()
        if isLandscape != viewModel.isLandscape {
            viewModel.updateOrientation(isLandscape: isLandscape)
            // Landscape arrangements have fewer rows.
            updateKeyboardHeight()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        viewModel.scheduleSpellcheckRefresh()
        viewModel.clipboardHistory.captureSystemPasteboard()
        let documentIdentifier = textDocumentProxy.optionalDocumentIdentifier
        if documentIdentifier != currentDocumentIdentifier {
            currentDocumentIdentifier = documentIdentifier
            viewModel.resetModeForCurrentField()
        }
    }

    /// Paints the controller's own band (below the keys) in the theme's
    /// background so it blends with the keyboard.
    private func applyBackgroundColor() {
        let defaults = SharedDefaults.store
        let style = defaults.string(forKey: SettingsKey.keyboardStyle.rawValue).flatMap(KeyboardStyle.init) ?? .classic
        guard style == .classic else {
            view.backgroundColor = .black
            return
        }
        let mode = defaults.string(forKey: SettingsKey.themeMode.rawValue).flatMap(ThemeMode.init) ?? .system
        let color = defaults.string(forKey: SettingsKey.themeColor.rawValue).flatMap(ThemeColor.init) ?? .system
        let systemScheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        let scheme = KeyboardPalette.colorScheme(mode: mode, scheme: systemScheme)
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        // UIColor(Color) resolves dynamic system colors for light mode, so the
        // system theme uses the UIKit color directly.
        let background = color == .system
            ? UIColor.systemBackground
            : UIColor(KeyboardPalette.resolve(color: color, mode: mode, scheme: systemScheme).background)
        view.backgroundColor = background.resolvedColor(with: traits)
    }

    /// Opens the Wurstfinger app. Keyboard extensions have no public API for
    /// this; the responder chain still reaches the host-side `UIApplication`,
    /// whose `openURL:options:completionHandler:` works (plain `openURL:` is
    /// ignored for extensions since iOS 17). Called through its implementation
    /// because the method is marked unavailable for extensions.
    private func openContainingApp(path: String) {
        guard let url = URL(string: "wurstfinger://\(path)") else { return }
        typealias OpenURL = @convention(c) (
            NSObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
        ) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        // UIScene has a method with the same selector but a different options
        // type, so only the application may receive this call.
        guard let applicationClass = NSClassFromString("UIApplication") else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: applicationClass), let implementation = current.method(for: selector) {
                let open = unsafeBitCast(implementation, to: OpenURL.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
    }

    /// Determines whether the host app is currently in a landscape orientation.
    ///
    /// On iPhone, `verticalSizeClass == .compact` is the canonical signal.
    /// On iPad, `verticalSizeClass` stays `.regular` in both orientations,
    /// so we fall back to the window scene's `interfaceOrientation`. The
    /// keyboard's own bounds are always shorter than tall and cannot be
    /// used as a substitute.
    private func detectIsLandscape() -> Bool {
        if traitCollection.userInterfaceIdiom == .pad {
            return view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
        }
        return traitCollection.verticalSizeClass == .compact
    }

    override var needsInputModeSwitchKey: Bool {
        true
    }

    private func configureHosting() {
        let rootView = DataDrivenKeyboardRootView(viewModel: viewModel, bottomGap: Self.bottomContentGap)
        let controller = UIHostingController(rootView: AnyView(rootView))
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear

        addChild(controller)
        view.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        controller.didMove(toParent: self)
        hostingController = controller
    }
}
