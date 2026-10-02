//
//  KeyAction.swift
//  Wurstfinger
//
//  All possible actions a key binding can trigger.
//

import Foundation

/// All possible actions a key binding can trigger.
enum KeyAction: Codable, Equatable {
    /// Insert text
    case commitText(String)

    /// Delete `trimCount` characters before the cursor, then insert `text`.
    /// Drives the space bar's multi-tap punctuation (" " → ", " → ". " → …),
    /// mirroring Thumb-Key's `ReplaceLastText`.
    case replaceLastText(String, trimCount: Int)

    /// Compose trigger (accent composition with previous character)
    case compose(trigger: String)

    /// Cycle through accents (ä → â → à → ...)
    case cycleAccents

    /// Switch to another mode by name.
    /// e.g. "shifted", "numeric", "emoji", "symbols", "main"
    case switchMode(String)

    /// Enter (`true`) or leave (`false`) the shifted layer. Leaving also
    /// releases caps lock.
    case toggleShift(Bool)

    /// Toggle caps lock. Turning it on also enters the shifted layer.
    case toggleCapsLock

    /// Thumb-Key's word capitalization toggle for the word before the cursor.
    /// Up: capitalizes the first letter, or uppercases the whole word when it is
    /// already capitalized. Down: lowercases the whole word.
    case toggleWordCapitalization(up: Bool)

    /// Next input method (system keyboard switcher)
    case advanceToNextInputMode

    /// Dismiss keyboard
    case dismissKeyboard

    /// Switch to the next enabled language
    case switchToNextLanguage

    /// Open the scrollable emoji panel
    case openEmoji

    /// Open the clipboard history panel
    case openClipboardHistory

    /// Open the Wurstfinger app's settings
    case openSettings

    /// Toggle hiding the letter legends
    case toggleHideLetters

    /// Cycle the keyboard position (left → split → center → right → left)
    case cycleKeyboardPosition

    /// Delete backward
    case deleteBackward

    /// Delete forward
    case deleteForward

    /// Delete the word before the cursor
    case deleteWordBackward

    /// Delete the word after the cursor
    case deleteWordForward

    /// Space
    case space

    /// Newline
    case newline

    /// Move cursor
    case moveCursor(offset: Int)

    /// Move the cursor to the start of the previous word
    case moveWordBackward

    /// Move the cursor past the next word
    case moveWordForward

    /// Move the cursor to the start / end of the current line
    case cursorToLineStart, cursorToLineEnd

    /// Move the cursor to the start / end of the whole text
    case cursorToTextStart, cursorToTextEnd

    /// Selection and history editing. These need the WurstSecure text bridge,
    /// since keyboard extensions have no API for them.
    case selectAll, selectLine, undo, redo

    /// Clipboard. With nothing selected, copy and cut act on the whole text.
    case copy, paste, cut

    /// No action (empty slot)
    case none
}
