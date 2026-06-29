//
//  EmojiPanelView.swift
//  Wurstfinger
//
//  Scrollable, categorized emoji picker shown when the emoji panel is active.
//  Reached via a swipe-up on the globe key. Inserts emoji directly into the
//  document and offers a back key (abc) plus a backspace.
//

import SwiftUI

/// A single emoji category with a section header symbol and its emoji.
struct EmojiCategory: Identifiable {
    let id = UUID()
    let symbolName: String
    let emojis: [String]
}

/// Curated emoji set grouped by category. Kept compact and dependency-free so
/// it works fully offline inside the keyboard extension's memory budget.
enum EmojiData {
    static let categories: [EmojiCategory] = [
        EmojiCategory(symbolName: "face.smiling", emojis: [
            "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃",
            "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😙",
            "😋", "😛", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔",
            "🤐", "🤨", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😌",
            "😔", "😪", "🤤", "😴", "😷", "🤒", "🤕", "🤢", "🤮", "🥵",
            "🥶", "😵", "🤯", "🤠", "🥳", "😎", "🤓", "🧐", "😕", "😟",
            "🙁", "😮", "😯", "😲", "😳", "🥺", "😦", "😧", "😨", "😰",
            "😥", "😢", "😭", "😱", "😖", "😣", "😞", "😓", "😩", "😫",
            "🥱", "😤", "😡", "😠", "🤬", "😈", "👿", "💀", "💩", "🤡",
        ]),
        EmojiCategory(symbolName: "hand.raised", emojis: [
            "👋", "🤚", "🖐️", "✋", "🖖", "👌", "🤏", "✌️", "🤞", "🤟",
            "🤘", "🤙", "👈", "👉", "👆", "👇", "☝️", "👍", "👎", "✊",
            "👊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "🤝", "🙏", "💪",
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
            "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "🔥",
        ]),
        EmojiCategory(symbolName: "pawprint", emojis: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
            "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🦆",
            "🦅", "🦉", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌",
            "🐞", "🐜", "🐢", "🐍", "🦎", "🐙", "🦑", "🦐", "🐠", "🐟",
            "🐬", "🐳", "🐋", "🦈", "🌵", "🌲", "🌳", "🌴", "🌱", "🌿",
            "🍀", "🌸", "🌹", "🌺", "🌻", "🌼", "🌷", "⭐️", "🌟", "✨",
        ]),
        EmojiCategory(symbolName: "fork.knife", emojis: [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐",
            "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🍆",
            "🥕", "🌽", "🌶️", "🥒", "🥬", "🥦", "🧄", "🧅", "🍄", "🥜",
            "🍞", "🥐", "🥖", "🧀", "🥚", "🍳", "🥞", "🧇", "🥓", "🍔",
            "🍟", "🍕", "🌭", "🥪", "🌮", "🌯", "🍝", "🍜", "🍲", "🍣",
            "🍦", "🍰", "🎂", "🍫", "🍬", "🍭", "🍩", "🍪", "☕️", "🍺",
        ]),
        EmojiCategory(symbolName: "airplane", emojis: [
            "⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸",
            "🥅", "🏒", "🏑", "🎯", "⛳️", "🎣", "🎽", "🎿", "🛷", "🥌",
            "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐",
            "🚚", "🚛", "🚜", "🛵", "🏍️", "🚲", "✈️", "🚀", "🛸", "🚁",
            "⛵️", "🚤", "🚢", "🏔️", "🌋", "🏕️", "🏖️", "🌃", "🌉", "🎡",
        ]),
        EmojiCategory(symbolName: "lightbulb", emojis: [
            "⌚️", "📱", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "💽", "💾", "📷",
            "📸", "🎥", "📺", "📻", "🎙️", "⏱️", "⏰", "🔋", "🔌", "💡",
            "🔦", "📔", "📖", "📚", "📝", "✏️", "🖊️", "📌", "📎", "🔑",
            "🔒", "🔓", "🔨", "🪓", "⚙️", "🧲", "🔭", "🔬", "💊", "🩹",
            "✅", "❌", "❓", "❗️", "💯", "🔆", "🎵", "🎶", "🎉", "🎈",
        ]),
    ]
}

/// The emoji picker UI shown in place of the keyboard grid.
struct EmojiPanelView: View {
    @ObservedObject var viewModel: KeyboardViewModel

    @State private var selectedCategory = 0

    private let columns = [GridItem(.adaptive(minimum: 38), spacing: 2)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(EmojiData.categories[selectedCategory].emojis, id: \.self) { emoji in
                        Button(action: { viewModel.insertEmoji(emoji) }, label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .contentShape(Rectangle())
                        })
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }

            Divider()

            HStack(spacing: 0) {
                Button(action: { viewModel.closeEmoji() }, label: {
                    Text("ABC")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                })
                .buttonStyle(.plain)

                Divider().frame(height: 28)

                ForEach(Array(EmojiData.categories.enumerated()), id: \.offset) { index, category in
                    Button(action: { selectedCategory = index }, label: {
                        Image(systemName: category.symbolName)
                            .font(.system(size: 16))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                            .foregroundStyle(selectedCategory == index ? Color.accentColor : Color.primary.opacity(0.6))
                    })
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 28)

                Button(action: { viewModel.emojiDeleteBackward() }, label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 17))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
            }
            .background(Color(.systemGray5).opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}
