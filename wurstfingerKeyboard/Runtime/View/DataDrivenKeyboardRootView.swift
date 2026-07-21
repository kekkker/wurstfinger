//
//  DataDrivenKeyboardRootView.swift
//  Wurstfinger
//
//  Root SwiftUI view that renders the data-driven keyboard using
//  KeyboardGridView. Replaces KeyboardRootView as the hosting target
//  in KeyboardViewController.
//

import SwiftUI

/// Root view for the data-driven keyboard path. Reads mode and arrangement
/// from the ViewModel and delegates all gesture callbacks back to it.
struct DataDrivenKeyboardRootView: View {
    @ObservedObject var viewModel: KeyboardViewModel

    /// Optional width override used by InteractiveKeyboardPreview.
    /// When nil, falls back to `viewModel.viewWidth`.
    var overrideWidth: CGFloat?

    @AppStorage(SettingsKey.keyboardStyle.rawValue, store: SharedDefaults.store)
    private var keyboardStyle: KeyboardStyle = .classic

    // Read layout settings straight from shared defaults so SwiftUI re-renders
    // the instant the host app changes them (cross-process), even when the
    // keyboard extension process is cached and `viewWillAppear` never re-fires.
    @AppStorage(SettingsKey.keyboardScale.rawValue, store: SharedDefaults.store)
    private var storedScale: Double = DeviceLayoutUtils.defaultKeyboardScale

    @AppStorage(SettingsKey.keyboardHorizontalPosition.rawValue, store: SharedDefaults.store)
    private var storedPosition: Double = DeviceLayoutUtils.defaultKeyboardPosition

    var body: some View {
        let screenBounds = DeviceLayoutUtils.screenBounds
        let screenShortestSide = min(screenBounds.width, screenBounds.height)
        let currentWidth = overrideWidth ?? viewModel.viewWidth
        let baseWidth = min(currentWidth, screenShortestSide)
        // In the in-app preview (overrideWidth set) keep using the view model so
        // the live sliders drive it; on the real keyboard read the shared store.
        let effectiveScale = overrideWidth != nil ? viewModel.keyboardScale : storedScale
        let effectivePosition = overrideWidth != nil ? viewModel.keyboardHorizontalPosition : storedPosition
        let scaledWidth = baseWidth * effectiveScale
        let availableSpace = currentWidth - scaledWidth
        let horizontalOffset = availableSpace * (effectivePosition - 0.5)

        ZStack {
            keyboardBackground
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                SpellcheckBar(
                    state: viewModel.spellcheckState,
                    onSuggestion: viewModel.acceptSpellcheckSuggestion
                )
                .frame(width: scaledWidth, height: KeyboardConstants.Layout.spellcheckBarHeight)
                .offset(x: horizontalOffset)

                if viewModel.emojiActive {
                    EmojiPanelView(viewModel: viewModel)
                        .padding(.horizontal, KeyboardConstants.Layout.horizontalPadding)
                        .padding(.top, KeyboardConstants.Layout.verticalPaddingTop)
                        .padding(.bottom, KeyboardConstants.Layout.verticalPaddingBottom)
                } else if let mode = viewModel.activeModeFromDefinition,
                   let arrangement = mode.arrangement(for: viewModel.currentContext) {
                    KeyboardGridView(
                        arrangement: arrangement,
                        keys: mode.keys,
                        onGesture: { key, gesture, isReturn in
                            viewModel.handleGesture(gesture, keyId: key.id, isReturn: isReturn)
                        },
                        onTouchDown: {
                            viewModel.feedbackTap()
                        },
                        onSlide: { key, phase in
                            viewModel.handleSlide(key, phase: phase)
                        }
                    )
                    .padding(.horizontal, KeyboardConstants.Layout.horizontalPadding)
                    .padding(.top, KeyboardConstants.Layout.verticalPaddingTop)
                    .padding(.bottom, KeyboardConstants.Layout.verticalPaddingBottom)
                    .frame(width: scaledWidth)
                    .offset(x: horizontalOffset)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Background

    @ViewBuilder
    private var keyboardBackground: some View {
        switch keyboardStyle {
        case .classic:
            Color(.systemBackground)
        case .liquidGlass:
            Color.clear
        }
    }
}
