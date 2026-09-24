//
//  AutoCapitalization.swift
//  wurstfingerKeyboard
//
//  Helper for auto-capitalization logic after sentence-ending punctuation.
//

import Foundation

enum AutoCapitalization {
    /// Punctuation that ends a sentence and triggers capitalization after space/newline.
    static let sentenceEnders: Set<Character> = [
        ".", "!", "?", // Standard Western punctuation
        "…", // Ellipsis
        "。", "！", "？", // CJK punctuation
    ]

    /// CJK sentence-ending punctuation. CJK text has no inter-sentence spaces,
    /// so these trigger capitalization even without trailing whitespace.
    static let cjkSentenceEnders: Set<Character> = [
        "。", "！", "？",
    ]

    /// Punctuation that opens a sentence and triggers immediate capitalization.
    static let sentenceOpeners: Set<Character> = [
        "¿", "¡", // Spanish inverted punctuation
    ]

    /// Whether the next character should be uppercase, following Android's
    /// `TextUtils.getCapsMode` (which Thumb-Key relies on) for the field's
    /// capitalization `mode`.
    ///
    /// Sentences start at the beginning of a paragraph, or after `.`, `!`, `?`
    /// (plus `…`) and whitespace. Opening quotes and brackets before the
    /// cursor and closing ones after the ender are skipped, and a period ending
    /// a word that contains another period ("e.g.") is treated as an
    /// abbreviation. CJK enders need no following space.
    static func shouldCapitalize(context: String?, mode: TextCapitalizationMode = .sentences) -> Bool {
        switch mode {
        case .none: return false
        case .allCharacters: return true
        case .words, .sentences: break
        }
        let characters = Array(context ?? "")

        // Back over opening punctuation right before the cursor.
        var cursor = characters.count
        while cursor > 0, isQuote(characters[cursor - 1]) || isPunctuation(characters[cursor - 1], .openPunctuation) {
            cursor -= 1
        }
        // Start of a paragraph, with optional spaces or tabs.
        var wordStart = cursor
        while wordStart > 0, characters[wordStart - 1] == " " || characters[wordStart - 1] == "\t" {
            wordStart -= 1
        }
        if wordStart == 0 || characters[wordStart - 1].isNewline {
            return true
        }
        if mode == .words {
            return cursor != wordStart
        }
        if cursor == wordStart {
            // No whitespace: only CJK enders, which take no space, count.
            return cjkSentenceEnders.contains(characters[cursor - 1])
        }
        // Back over closing punctuation after the sentence ender.
        var end = wordStart
        while end > 0, isQuote(characters[end - 1]) || isPunctuation(characters[end - 1], .closePunctuation) {
            end -= 1
        }
        guard end > 0, sentenceEnders.contains(characters[end - 1]) else { return false }
        if characters[end - 1] == "." {
            // A word that ends with a period but contains another one is an abbreviation.
            var index = end - 2
            while index >= 0 {
                if characters[index] == "." {
                    return false
                }
                if !characters[index].isLetter {
                    break
                }
                index -= 1
            }
        }
        return true
    }

    private static func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "'"
    }

    private static func isPunctuation(_ character: Character, _ category: Unicode.GeneralCategory) -> Bool {
        character.unicodeScalars.first?.properties.generalCategory == category
    }

    /// Determines if the next character should be capitalized immediately (without space).
    /// This is used for Spanish inverted punctuation (¿ and ¡).
    static func shouldCapitalizeImmediately(after character: String) -> Bool {
        // Only check single characters
        guard let char = character.first, character.count == 1 else { return false }
        return sentenceOpeners.contains(char)
    }
}
