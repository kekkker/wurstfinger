//
//  DataDrivenKeyboardRootView.swift
//  Wurstfinger
//
//  Root SwiftUI view that renders the data-driven keyboard using
//  KeyboardGridView, plus the emoji and clipboard panels.
//

import SwiftUI

/// Root view for the data-driven keyboard path. Reads mode and arrangement
/// from the ViewModel and delegates all gesture callbacks back to it.
struct DataDrivenKeyboardRootView: View {
    @ObservedObject var viewModel: KeyboardViewModel

    /// Optional width override used by InteractiveKeyboardPreview.
    /// When nil, falls back to `viewModel.viewWidth`.
    var overrideWidth: CGFloat?

    /// Empty space below the keys, painted with the keyboard background so
    /// it follows theme changes live.
    var bottomGap: CGFloat = 0

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.displayScale) private var displayScale

    @AppStorage(SettingsKey.keyboardStyle.rawValue, store: SharedDefaults.store)
    private var keyboardStyle: KeyboardStyle = .classic

    // Read layout settings straight from shared defaults so SwiftUI re-renders
    // the instant the host app changes them (cross-process), even when the
    // keyboard extension process is cached and `viewWillAppear` never re-fires.
    @AppStorage(SettingsKey.keyboardScale.rawValue, store: SharedDefaults.store)
    private var storedScale: Double = DeviceLayoutUtils.defaultKeyboardScale

    @AppStorage(SettingsKey.keyboardHorizontalPosition.rawValue, store: SharedDefaults.store)
    private var storedPosition: Double = DeviceLayoutUtils.defaultKeyboardPosition

    @AppStorage(SettingsKey.keyAspectRatio.rawValue, store: SharedDefaults.store)
    private var storedAspectRatio: Double = DeviceLayoutUtils.defaultKeyAspectRatio

    @AppStorage(SettingsKey.keyboardSplit.rawValue, store: SharedDefaults.store)
    private var keyboardSplit = false

    @AppStorage(SettingsKey.bottomOffset.rawValue, store: SharedDefaults.store)
    private var bottomOffset: Double = 0

    @AppStorage(SettingsKey.backdropEnabled.rawValue, store: SharedDefaults.store)
    private var backdropEnabled = false

    @AppStorage(SettingsKey.themeMode.rawValue, store: SharedDefaults.store)
    private var themeMode: ThemeMode = .system

    @AppStorage(SettingsKey.themeColor.rawValue, store: SharedDefaults.store)
    private var themeColor: ThemeColor = .system

    @AppStorage(SettingsKey.hideLetters.rawValue, store: SharedDefaults.store)
    private var hideLetters = false

    @AppStorage(SettingsKey.hideSymbols.rawValue, store: SharedDefaults.store)
    private var hideSymbols = false

    @AppStorage(SettingsKey.keyPadding.rawValue, store: SharedDefaults.store)
    private var keyPadding: Double = LookSettings().keyPadding

    @AppStorage(SettingsKey.keyBorderWidth.rawValue, store: SharedDefaults.store)
    private var keyBorderWidth: Double = LookSettings().keyBorderWidth

    @AppStorage(SettingsKey.keyRadius.rawValue, store: SharedDefaults.store)
    private var keyRadius: Double = LookSettings().keyRadius

    @AppStorage(SettingsKey.animationSpeed.rawValue, store: SharedDefaults.store)
    private var animationSpeed: Double = LookSettings().animationSpeed

    @AppStorage(SettingsKey.animationHelperSpeed.rawValue, store: SharedDefaults.store)
    private var animationHelperSpeed: Double = LookSettings().animationHelperSpeed

    var body: some View {
        let screenBounds = DeviceLayoutUtils.screenBounds
        let screenShortestSide = min(screenBounds.width, screenBounds.height)
        let currentWidth = overrideWidth ?? viewModel.viewWidth
        let baseWidth = min(currentWidth, screenShortestSide)
        // In the in-app preview (overrideWidth set) keep using the view model so
        // the live sliders drive it; on the real keyboard read the shared store.
        let isPreview = overrideWidth != nil
        let effectiveScale = isPreview ? viewModel.keyboardScale : storedScale
        let effectivePosition = isPreview ? viewModel.keyboardHorizontalPosition : storedPosition
        let aspectRatio = isPreview ? viewModel.keyAspectRatio : storedAspectRatio
        let scaledWidth = baseWidth * effectiveScale
        let availableSpace = currentWidth - scaledWidth
        let horizontalOffset = availableSpace * (effectivePosition - 0.5)
        let keyHeight = KeyboardConstants.Calculations.keyHeight(aspectRatio: aspectRatio) * effectiveScale
        let palette = resolvedPalette

        ZStack(alignment: .top) {
            keyboardBackground(palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                if backdropEnabled {
                    palette.surfaceVariant
                        .frame(height: 1)
                    Color.clear
                        .frame(height: KeyboardConstants.Layout.backdropTopPadding - 1)
                }

                SpellcheckBar(
                    state: viewModel.spellcheckState,
                    onSuggestion: viewModel.acceptSpellcheckSuggestion,
                    palette: palette
                )
                .frame(width: scaledWidth, height: KeyboardConstants.Layout.spellcheckBarHeight)
                .offset(x: keyboardSplit ? 0 : horizontalOffset)

                if viewModel.emojiActive {
                    EmojiPanelView(viewModel: viewModel, keyHeight: keyHeight, look: look(palette))
                        .frame(height: keyHeight * CGFloat(KeyboardConstants.KeyDimensions.totalRows))
                        .frame(width: keyboardSplit ? currentWidth : scaledWidth)
                        .offset(x: keyboardSplit ? 0 : horizontalOffset)
                } else if viewModel.clipboardActive {
                    ClipboardPanelView(viewModel: viewModel, history: viewModel.clipboardHistory, palette: palette)
                        .frame(height: keyHeight * CGFloat(KeyboardConstants.KeyDimensions.totalRows))
                        .frame(width: keyboardSplit ? currentWidth : scaledWidth)
                        .offset(x: keyboardSplit ? 0 : horizontalOffset)
                } else if keyboardSplit {
                    // Thumb-Key's "dual" position: one copy per thumb.
                    HStack(spacing: 0) {
                        grid(keyHeight: keyHeight, palette: palette)
                            .frame(width: min(scaledWidth, currentWidth / 2))
                        Spacer(minLength: 0)
                        grid(keyHeight: keyHeight, palette: palette)
                            .frame(width: min(scaledWidth, currentWidth / 2))
                    }
                    .frame(width: currentWidth)
                } else {
                    grid(keyHeight: keyHeight, palette: palette)
                        .frame(width: scaledWidth)
                        .offset(x: horizontalOffset)
                }

                Color.clear
                    .frame(height: bottomOffset + bottomGap)
            }

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(palette.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(palette.primary.opacity(0.9)))
                    .padding(.top, KeyboardConstants.Layout.spellcheckBarHeight + keyHeight)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, KeyboardPalette.colorScheme(mode: themeMode, scheme: systemColorScheme))
    }

    // MARK: - Pieces

    private var resolvedPalette: KeyboardPalette {
        KeyboardPalette.resolve(color: themeColor, mode: themeMode, scheme: systemColorScheme)
    }

    private func look(_ palette: KeyboardPalette) -> KeyLook {
        KeyLook(
            settings: LookSettings(
                themeMode: themeMode,
                themeColor: themeColor,
                hideLetters: hideLetters,
                hideSymbols: hideSymbols,
                keyPadding: keyPadding,
                keyBorderWidth: keyBorderWidth,
                keyRadius: keyRadius,
                animationSpeed: animationSpeed,
                animationHelperSpeed: animationHelperSpeed
            ),
            palette: palette,
            style: keyboardStyle,
            capsLock: viewModel.activeModeName == ModeNames.capsLock,
            isSecureField: viewModel.textInputTarget?.isSecureTextEntry ?? false
        )
    }

    @ViewBuilder
    private func grid(keyHeight: CGFloat, palette: KeyboardPalette) -> some View {
        if let mode = viewModel.activeModeFromDefinition,
           let arrangement = mode.arrangement(for: viewModel.currentContext) {
            KeyboardGridView(
                arrangement: arrangement,
                keys: mode.keys,
                look: look(palette),
                keyHeight: keyHeight,
                makeGestureConfig: { key, keySize in
                    viewModel.gestureConfig(for: key, keySize: keySize, pixelScale: displayScale)
                },
                onTouchDown: {
                    viewModel.feedbackTap()
                },
                onEvent: { key, event in
                    viewModel.handleKeyEvent(event, keyId: key.id)
                }
            )
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func keyboardBackground(_ palette: KeyboardPalette) -> some View {
        switch keyboardStyle {
        case .classic:
            palette.background
        case .liquidGlass:
            Color.clear
        }
    }
}
