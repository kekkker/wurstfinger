//
//  EmojiPanelView.swift
//  Wurstfinger
//
//  Thumb-Key's emoji screen: a scrollable, categorized picker with recently
//  used emoji, next to a column of ABC, 123, backspace and return keys.
//

import SwiftUI

/// One emoji category with its tab symbol.
struct EmojiCategory: Identifiable {
    let id: String
    let symbolName: String
    let emojis: [String]

    init(id: String, symbolName: String, emojis: [String]) {
        self.id = id
        self.symbolName = symbolName
        self.emojis = emojis
    }

    /// Builds a category from space-separated emoji (generated data).
    init(id: String, symbolName: String, packed: String) {
        self.init(id: id, symbolName: symbolName, emojis: packed.split(separator: " ").map(String.init))
    }
}

/// The emoji picker shown in place of the keyboard grid.
struct EmojiPanelView: View {
    @ObservedObject var viewModel: KeyboardViewModel
    /// Height of each of the four side keys; together they fill the panel.
    let keyHeight: CGFloat
    let look: KeyLook

    @State private var selectedCategoryId: String?
    @Environment(\.displayScale) private var displayScale

    private static let recentId = "recent"
    private static let backKey = KeyConfig.utility(
        "emojiBack", label: NumericLayouts.defaultBackToAlphaLabel, action: .none
    )

    private var categories: [EmojiCategory] {
        let recent = RecentEmoji.load(from: viewModel.sharedDefaults)
        let recentCategory = recent.isEmpty
            ? []
            : [EmojiCategory(id: Self.recentId, symbolName: "clock", emojis: recent)]
        return recentCategory + EmojiCategory.generated
    }

    var body: some View {
        let categories = categories
        let selected = categories.first { $0.id == selectedCategoryId } ?? categories[0]

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                categoryTabs(categories, selected: selected)
                emojiGrid(selected)
            }
            .background(look.palette.surface)

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    sideKey(Self.backKey, width: proxy.size.width) { event in
                        if event == .tap {
                            viewModel.closeEmoji()
                        }
                        return nil
                    }
                    ForEach([UtilitySlot.symbols, UtilitySlot.delete, UtilitySlot.return], id: \.self) { keyId in
                        if let key = viewModel.currentDefinition?.mode(ModeNames.main)?.key(for: keyId) {
                            sideKey(key, width: proxy.size.width) { event in
                                viewModel.handleEmojiPanelKeyEvent(event, key: key)
                            }
                        }
                    }
                }
            }
            .frame(width: keyHeight * 1.2)
        }
    }

    private func categoryTabs(_ categories: [EmojiCategory], selected: EmojiCategory) -> some View {
        HStack(spacing: 0) {
            ForEach(categories) { category in
                Button {
                    selectedCategoryId = category.id
                } label: {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(category.id == selected.id ? look.palette.primary : look.palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.id)
            }
        }
        .background(look.palette.surfaceVariant)
    }

    private func emojiGrid(_ category: EmojiCategory) -> some View {
        ScrollViewReader { reader in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 0)], spacing: 0) {
                    ForEach(category.emojis, id: \.self) { emoji in
                        Button {
                            viewModel.insertEmoji(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .id(category.id)
                .padding(.horizontal, 2)
            }
            .onChange(of: category.id) { id in
                reader.scrollTo(id, anchor: .top)
            }
        }
    }

    private func sideKey(_ key: KeyConfig, width _: CGFloat, onEvent: @escaping (KeyGestureEvent) -> KeyAction?) -> some View {
        KeyView(
            key: key,
            look: look,
            height: keyHeight,
            makeGestureConfig: { key, keySize in
                viewModel.gestureConfig(for: key, keySize: keySize, pixelScale: displayScale)
            },
            onTouchDown: { viewModel.feedbackTap() },
            onEvent: { _, event in onEvent(event) }
        )
    }
}
