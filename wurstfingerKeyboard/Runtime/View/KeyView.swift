//
//  KeyView.swift
//  Wurstfinger
//
//  Draws one key the way Thumb-Key does and feeds its touches into a
//  gesture session.
//

import SwiftUI

/// Look-and-feel settings (Thumb-Key defaults).
struct LookSettings: Equatable {
    var themeMode = ThemeMode.system
    var themeColor = ThemeColor.system
    var hideLetters = false
    var hideSymbols = false
    /// Gap around each key, in points.
    var keyPadding: Double = 0
    /// Border width in tenths of a point (Thumb-Key's unit).
    var keyBorderWidth: Double = 1
    /// Corner radius as a percentage of half the key size.
    var keyRadius: Double = 0
    /// Press animation durations, in milliseconds.
    var animationSpeed: Double = 250
    var animationHelperSpeed: Double = 250

    static let keyPaddingRange = 0.0 ... 10.0
    static let keyBorderWidthRange = 0.0 ... 50.0
    static let keyRadiusRange = 0.0 ... 100.0
    static let animationSpeedRange = 0.0 ... 500.0
}

/// Everything shared by all keys for one render.
struct KeyLook {
    var settings = LookSettings()
    var palette = KeyboardPalette.system
    var style = KeyboardStyle.classic
    /// Caps lock is on (switches the shift key's legend).
    var capsLock = false
    /// The focused field hides its text; no press animation then.
    var isSecureField = false
}

/// Generic key view that renders any `KeyConfig`.
///
/// Legends derive directly from `key.bindings`, so only the gestures actually
/// defined on a key are shown.
struct KeyView: View {
    let key: KeyConfig
    let look: KeyLook
    /// Key height in points.
    let height: CGFloat
    /// Width in grid columns over height in rows (e.g. 3 for the space bar).
    var spanRatio: CGFloat = 1.0
    let makeGestureConfig: (KeyConfig, CGFloat) -> KeyGestureConfig
    let onTouchDown: () -> Void
    /// Handles a gesture event and returns the action it performed.
    let onEvent: (KeyConfig, KeyGestureEvent) -> KeyAction?

    @State private var isActive = false
    @State private var releasedText: String?
    @State private var releaseOpacity: Double = 0
    @State private var releaseOffset: CGFloat = 0
    @State private var releaseGeneration = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let padding = CGFloat(look.settings.keyPadding)
            let width = max(0, proxy.size.width - 2 * padding)
            let keyHeight = max(0, proxy.size.height - 2 * padding)
            let borderWidth = CGFloat(look.settings.keyBorderWidth / 10)
            // Thumb-Key sizes legends from the average of one column's width and the height.
            let keySize = max(0, (width / spanRatio + keyHeight) / 2 - borderWidth)

            ZStack {
                background(width: width, height: keyHeight, borderWidth: borderWidth)
                legends(keySize: keySize, borderWidth: borderWidth)
                pressAnimation(keySize: keySize, height: keyHeight)
            }
            .frame(width: width, height: keyHeight)
            .clipShape(keyShape(width: width, height: keyHeight))
            .padding(padding)
            .contentShape(Rectangle())
            .modifier(KeyTouchHandler(
                makeConfig: { makeGestureConfig(key, keySize) },
                pixelScale: displayScale,
                onTouchDown: onTouchDown,
                onEvent: { event in
                    let action = onEvent(key, event)
                    if case let .commitText(text)? = action {
                        animateRelease(text, height: keyHeight)
                    }
                },
                isActive: $isActive
            ))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(key.id)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Labels

    /// Primary text shown on the key. Falls back to the key id (so
    /// unconfigured keys are still visible during development).
    var primaryLabel: String {
        key.bindings[.tap]?.label ?? key.id
    }

    var accessibilityLabel: String {
        if let tap = key.bindings[.tap], let custom = tap.accessibilityLabel {
            return custom
        }
        return primaryLabel
    }

    // MARK: - Background

    private func keyShape(width: CGFloat, height: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: CGFloat(look.settings.keyRadius / 100) * (width + height) / 4)
    }

    @ViewBuilder
    private func background(width: CGFloat, height: CGFloat, borderWidth: CGFloat) -> some View {
        let shape = keyShape(width: width, height: height)
        let palette = look.palette
        switch look.style {
        case .classic:
            let fill = isActive
                ? palette.inversePrimary
                : (key.style == .primary || key.style == .accent || key.style == .secondary
                    ? palette.surface
                    : palette.surfaceVariant)
            shape.fill(fill)
                .overlay(shape.strokeBorder(palette.outline, lineWidth: borderWidth))
        case .liquidGlass:
            shape.fill(.bar)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .overlay(isActive ? shape.fill(palette.inversePrimary.opacity(0.5)) : nil)
        }
    }

    // MARK: - Legends

    /// What to draw for one legend.
    private enum LegendContent {
        case text(String, Color)
        case icon(String, Color)
    }

    private static let legendAlignments: [(GestureType, Alignment)] = [
        (.swipeUpLeft, .topLeading), (.swipeUp, .top), (.swipeUpRight, .topTrailing),
        (.swipeLeft, .leading), (.swipeRight, .trailing),
        (.swipeDownLeft, .bottomLeading), (.swipeDown, .bottom), (.swipeDownRight, .bottomTrailing),
    ]

    private func legends(keySize: CGFloat, borderWidth: CGFloat) -> some View {
        // Thumb-Key's insets: cardinal legends hug the edges, diagonal ones move
        // inwards as corners get rounder so they stay clear of the curve.
        let xPadding = 2 + borderWidth
        let yPadding = borderWidth
        let radiusFraction = CGFloat(look.settings.keyRadius / 100)
        let diagonalX = xPadding + 20 * radiusFraction
        let diagonalY = yPadding + 20 * radiusFraction

        return ZStack {
            ForEach(Self.legendAlignments, id: \.0) { gesture, alignment in
                if let binding = key.bindings[gesture], let content = swipeLegend(for: binding) {
                    let isDiagonal = alignment == .topLeading || alignment == .topTrailing
                        || alignment == .bottomLeading || alignment == .bottomTrailing
                    legendView(content, size: keySize / 5)
                        .padding(.horizontal, alignment == .top || alignment == .bottom ? 0 : (isDiagonal ? diagonalX : xPadding))
                        .padding(.vertical, alignment == .leading || alignment == .trailing ? 0 : (isDiagonal ? diagonalY : yPadding))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                }
            }
            if let content = centerLegend {
                legendView(content, size: keySize / 2.5)
            }
        }
    }

    private var centerLegend: LegendContent? {
        guard key.style != .spacebar, let tap = key.bindings[.tap] else { return nil }
        switch tap.legend {
        case let .icon(name):
            return .icon(name, look.palette.secondary)
        case let .capsIcon(name, capsLockIcon):
            return .icon(look.capsLock ? capsLockIcon : name, look.palette.secondary)
        case .hidden:
            return nil
        case .muted, nil:
            return visibleText(tap.label, color: look.palette.primary)
        }
    }

    private func swipeLegend(for binding: KeyBinding) -> LegendContent? {
        switch binding.legend {
        case .hidden:
            nil
        case let .icon(name):
            .icon(name, look.palette.muted)
        case let .capsIcon(name, capsLockIcon):
            .icon(look.capsLock ? capsLockIcon : name, look.palette.muted)
        case .muted:
            visibleText(binding.label, color: look.palette.muted)
        case nil:
            visibleText(binding.label, color: look.palette.secondary)
        }
    }

    /// Text legend unless hidden: letters by "hide letters", symbols by
    /// "hide symbols"; digits always show.
    private func visibleText(_ text: String, color: Color) -> LegendContent? {
        guard !text.isEmpty else { return nil }
        let hidden = if text.contains(where: \.isLetter) {
            look.settings.hideLetters
        } else if text.contains(where: \.isNumber) {
            false
        } else {
            look.settings.hideSymbols
        }
        return hidden ? nil : .text(text, color)
    }

    @ViewBuilder
    private func legendView(_ content: LegendContent, size: CGFloat) -> some View {
        switch content {
        case let .text(text, color):
            // Thumb-Key draws uppercase letters slightly smaller.
            let fontSize = text.first?.isUppercase == true ? size * 0.8 : size
            Text(text)
                .font(.system(size: max(1, fontSize), weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
        case let .icon(name, color):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .frame(width: size * 0.85, height: size * 0.85)
                .frame(width: size, height: size)
        }
    }

    // MARK: - Press Animation

    /// Thumb-Key's release animation: the key flashes and the typed text drops
    /// in, then both fade out.
    @ViewBuilder
    private func pressAnimation(keySize: CGFloat, height _: CGFloat) -> some View {
        if let releasedText {
            ZStack {
                look.palette.tertiaryContainer
                Text(releasedText)
                    .font(.system(size: max(1, keySize / 2.5), weight: .bold))
                    .foregroundColor(look.palette.tertiary)
                    .lineLimit(1)
                    .offset(y: releaseOffset)
            }
            .opacity(releaseOpacity)
            .allowsHitTesting(false)
        }
    }

    private func animateRelease(_ text: String, height: CGFloat) {
        guard !look.isSecureField, look.style == .classic else { return }
        let speed = look.settings.animationSpeed / 1000
        let helper = look.settings.animationHelperSpeed / 1000
        releaseGeneration += 1
        let generation = releaseGeneration
        releasedText = text
        releaseOpacity = 1
        releaseOffset = -height / 2
        DispatchQueue.main.async {
            withAnimation(.linear(duration: speed)) {
                releaseOffset = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + helper) {
            guard generation == releaseGeneration else { return }
            withAnimation(.easeOut(duration: speed)) {
                releaseOpacity = 0
            }
        }
    }
}
