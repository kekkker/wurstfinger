//
//  CommonKeys.swift
//  Wurstfinger
//
//  Shared key definitions reusable across all MessagEase languages.
//

import Foundation

/// Shared key definitions reusable across all MessagEase languages.
/// Utility keys and default punctuation/symbol bindings for the 3x3 grid.
enum CommonKeys {
    // MARK: - Utility Keys

    /// A binding that shows `icon` as its legend.
    static func iconBinding(
        _ action: KeyAction,
        icon: String,
        returnAction: KeyAction? = nil,
        accessibilityLabel: String? = nil
    ) -> KeyBinding {
        KeyBinding(
            label: "", action: action, category: .utility,
            returnAction: returnAction, accessibilityLabel: accessibilityLabel,
            legend: .icon(icon)
        )
    }

    /// A binding with no legend (e.g. the space bar's cursor swipes).
    static func hiddenBinding(_ action: KeyAction, returnAction: KeyAction? = nil) -> KeyBinding {
        KeyBinding(
            label: "", action: action, category: .utility,
            returnAction: returnAction, accessibilityLabel: nil, legend: .hidden
        )
    }

    /// Thumb-Key's emoji key ("special action" key), in the globe slot:
    /// tap opens emoji; ↑ settings, ↖ hide letters, ← next language,
    /// → move keyboard, ↓ switch keyboard, ↙ hide keyboard (Thumb-Key has
    /// voice input there, which iOS keyboards cannot offer).
    static let globe = KeyConfig(
        id: UtilitySlot.globe,
        bindings: [
            .tap: iconBinding(.openEmoji, icon: "face.smiling", accessibilityLabel: String(localized: "Emoji")),
            .swipeUp: iconBinding(.openSettings, icon: "gearshape", accessibilityLabel: String(localized: "Settings")),
            .swipeUpLeft: iconBinding(.toggleHideLetters, icon: "eye.slash", accessibilityLabel: String(localized: "Hide letters")),
            .swipeLeft: iconBinding(.switchToNextLanguage, icon: "globe", accessibilityLabel: String(localized: "Switch language")),
            .swipeRight: iconBinding(
                .cycleKeyboardPosition, icon: "arrow.left.and.right",
                accessibilityLabel: String(localized: "Move keyboard")
            ),
            .swipeDown: iconBinding(
                .advanceToNextInputMode, icon: "keyboard",
                accessibilityLabel: String(localized: "Switch keyboard")
            ),
            .swipeDownLeft: iconBinding(
                .dismissKeyboard, icon: "keyboard.chevron.compact.down",
                accessibilityLabel: String(localized: "Hide keyboard")
            ),
        ],
        swipeMode: .eightWay,
        slideType: .none,
        style: .utility,
        tapCycleActions: nil
    )

    /// Thumb-Key's backspace: ← / → delete a word, long press deletes a word,
    /// sliding selects text to delete.
    static let delete = KeyConfig(
        id: UtilitySlot.delete,
        bindings: [
            .tap: iconBinding(.deleteBackward, icon: "delete.left", accessibilityLabel: String(localized: "Delete")),
            .swipeLeft: hiddenBinding(.deleteWordBackward),
            .swipeRight: hiddenBinding(.deleteWordForward),
            .longPress: hiddenBinding(.deleteWordBackward),
        ],
        swipeMode: .twoWayHorizontal,
        slideType: .delete,
        style: .utility,
        tapCycleActions: nil
    )

    /// Return. iOS runs the field's return action for a newline, so tap and
    /// Thumb-Key's long-press newline are the same here.
    static let `return` = KeyConfig(
        id: UtilitySlot.return,
        bindings: [
            .tap: iconBinding(.newline, icon: "arrow.turn.down.left", accessibilityLabel: String(localized: "New line")),
            .longPress: hiddenBinding(.newline),
        ],
        swipeMode: .eightWay,
        slideType: .none,
        style: .utility,
        tapCycleActions: nil
    )

    /// Thumb-Key's text-edit swipes, shared by the 123 key and the numeric
    /// layer's back key: ↑ copy, ↖ select all (return: select line), ↗ cut,
    /// ↙ undo, ↘ redo, ↓ paste (return: clipboard history).
    static let textEditSwipes: [GestureType: KeyBinding] = [
        .swipeUp: iconBinding(.copy, icon: "doc.on.doc", accessibilityLabel: String(localized: "Copy")),
        .swipeUpLeft: iconBinding(
            .selectAll, icon: "rectangle.dashed", returnAction: .selectLine,
            accessibilityLabel: String(localized: "Select all")
        ),
        .swipeUpRight: iconBinding(.cut, icon: "scissors", accessibilityLabel: String(localized: "Cut")),
        .swipeDownLeft: iconBinding(.undo, icon: "arrow.uturn.backward", accessibilityLabel: String(localized: "Undo")),
        .swipeDownRight: iconBinding(.redo, icon: "arrow.uturn.forward", accessibilityLabel: String(localized: "Redo")),
        .swipeDown: iconBinding(
            .paste, icon: "doc.on.clipboard", returnAction: .openClipboardHistory,
            accessibilityLabel: String(localized: "Paste")
        ),
    ]

    static let symbols = KeyConfig.utility(
        UtilitySlot.symbols, label: "123", action: .switchMode(ModeNames.numeric),
        swipeMode: .eightWay,
        swipes: textEditSwipes
    )

    /// Thumb-Key's multi-tap sequence on the space bar: each further tap
    /// within a second replaces the previous insertion.
    static let spacebarTapCycle: [KeyAction] = [
        .replaceLastText(", ", trimCount: 1),
        .replaceLastText(". ", trimCount: 2),
        .replaceLastText("? ", trimCount: 2),
        .replaceLastText("! ", trimCount: 2),
        .replaceLastText(": ", trimCount: 2),
        .replaceLastText("; ", trimCount: 2),
    ]

    /// Thumb-Key's space bar: ← / → move the cursor, ↙ / ↘ by word, ↑ / ↓ to
    /// the line start / end (returning: text start / end). No legends.
    static let spacebar = KeyConfig(
        id: UtilitySlot.space,
        bindings: [
            .tap: KeyBinding(
                label: "␣", action: .space, category: .utility,
                returnAction: nil, accessibilityLabel: String(localized: "Space")
            ),
            .swipeLeft: hiddenBinding(.moveCursor(offset: -1)),
            .swipeRight: hiddenBinding(.moveCursor(offset: 1)),
            .swipeDownLeft: hiddenBinding(.moveWordBackward),
            .swipeDownRight: hiddenBinding(.moveWordForward),
            .swipeUp: hiddenBinding(.cursorToLineStart, returnAction: .cursorToTextStart),
            .swipeDown: hiddenBinding(.cursorToLineEnd, returnAction: .cursorToTextEnd),
        ],
        swipeMode: .eightWay,
        slideType: .moveCursor,
        style: .spacebar,
        tapCycleActions: spacebarTapCycle
    )

    /// All utility keys as dictionary, mergeable with language keys.
    static let allUtilityKeys: [String: KeyConfig] = [
        UtilitySlot.globe: globe,
        UtilitySlot.delete: delete,
        UtilitySlot.return: `return`,
        UtilitySlot.symbols: symbols,
        UtilitySlot.space: spacebar,
    ]

    // MARK: - Shift

    /// Shift bindings on the midRight key, per layer, from Thumb-Key: ↑ shifts
    /// (on the shifted layer: toggles caps lock), ↓ unshifts. Returning
    /// swipes capitalize or lowercase the word before the cursor.
    static let shiftUp = KeyBinding(
        label: "", action: .toggleShift(true), category: .modifier,
        returnAction: .toggleWordCapitalization(up: true),
        accessibilityLabel: String(localized: "Shift"), legend: .icon("arrowtriangle.up.fill")
    )
    static let capsLockToggle = KeyBinding(
        label: "", action: .toggleCapsLock, category: .modifier,
        returnAction: .toggleWordCapitalization(up: true),
        accessibilityLabel: String(localized: "Caps lock"), legend: .capsIcon("capslock", capsLockIcon: "c.circle")
    )
    /// Unshift on the main layer has no legend.
    static let shiftDownHidden = KeyBinding(
        label: "", action: .toggleShift(false), category: .modifier,
        returnAction: .toggleWordCapitalization(up: false),
        accessibilityLabel: nil, legend: .hidden
    )
    static let shiftDown = KeyBinding(
        label: "", action: .toggleShift(false), category: .modifier,
        returnAction: .toggleWordCapitalization(up: false),
        accessibilityLabel: String(localized: "Unshift"), legend: .icon("arrowtriangle.down.fill")
    )

    // MARK: - Default Slot Bindings

    /// Shared punctuation, symbol, compose, and action bindings for each grid slot.
    /// The factory merges these with language-specific center characters.
    /// Each KeyBinding includes both the primary action and an optional return-swipe action.
    static let defaultSlotBindings: [String: [GestureType: KeyBinding]] = [
        // MARK: topLeft

        GridSlot.topLeft: [
            .swipeUpLeft: KeyBinding(
                label: "\u{1F152}", action: .cycleAccents, category: .compose,
                returnAction: .cycleAccents, accessibilityLabel: nil
            ),
            .swipeRight: KeyBinding(
                label: "-", action: .commitText("-"), category: nil,
                returnAction: .commitText("÷"), accessibilityLabel: nil
            ),
            .swipeDownLeft: KeyBinding(
                label: "$", action: .compose(trigger: "$"), category: .compose,
                returnAction: .commitText("¥"), accessibilityLabel: nil
            ),
        ],

        // MARK: topCenter

        GridSlot.topCenter: [
            .swipeUpLeft: KeyBinding(
                label: "`", action: .compose(trigger: "ˋ"), category: .compose,
                returnAction: .commitText("\u{2018}"), accessibilityLabel: nil
            ),
            .swipeUp: KeyBinding(
                label: "^", action: .compose(trigger: "^"), category: .compose,
                returnAction: .commitText("ˆ"), accessibilityLabel: nil
            ),
            .swipeUpRight: KeyBinding(
                label: "´", action: .compose(trigger: "´"), category: .compose,
                returnAction: .commitText("\u{2019}"), accessibilityLabel: nil
            ),
            .swipeRight: KeyBinding(
                label: "!", action: .commitText("!"), category: nil,
                returnAction: .commitText("¡"), accessibilityLabel: nil
            ),
            .swipeDownRight: KeyBinding(
                label: "\\", action: .commitText("\\"), category: nil,
                returnAction: .commitText("—"), accessibilityLabel: nil
            ),
            .swipeDownLeft: KeyBinding(
                label: "/", action: .commitText("/"), category: nil,
                returnAction: .commitText("–"), accessibilityLabel: nil
            ),
            .swipeLeft: KeyBinding(
                label: "+", action: .commitText("+"), category: nil,
                returnAction: .commitText("×"), accessibilityLabel: nil
            ),
        ],

        // MARK: topRight

        GridSlot.topRight: [
            .swipeUpRight: KeyBinding(
                label: "", action: .commitText("\n"), category: nil,
                returnAction: .commitText("\n"), accessibilityLabel: nil
            ),
            .swipeDownRight: KeyBinding(
                label: "€", action: .commitText("€"), category: nil,
                returnAction: .commitText("£"), accessibilityLabel: nil
            ),
            .swipeDown: KeyBinding(
                label: "=", action: .commitText("="), category: nil,
                returnAction: .commitText("±"), accessibilityLabel: nil
            ),
            .swipeLeft: KeyBinding(
                label: "?", action: .commitText("?"), category: nil,
                returnAction: .commitText("¿"), accessibilityLabel: nil
            ),
        ],

        // MARK: midLeft

        GridSlot.midLeft: [
            .swipeUpLeft: KeyBinding(
                label: "{", action: .commitText("{"), category: nil,
                returnAction: .commitText("}"), accessibilityLabel: nil
            ),
            .swipeUpRight: KeyBinding(
                label: "%", action: .commitText("%"), category: nil,
                returnAction: .commitText("‰"), accessibilityLabel: nil
            ),
            .swipeDownRight: KeyBinding(
                label: "_", action: .commitText("_"), category: nil,
                returnAction: .commitText("¬"), accessibilityLabel: nil
            ),
            .swipeDownLeft: KeyBinding(
                label: "[", action: .commitText("["), category: nil,
                returnAction: .commitText("]"), accessibilityLabel: nil
            ),
            .swipeLeft: KeyBinding(
                label: "(", action: .commitText("("), category: nil,
                returnAction: .commitText(")"), accessibilityLabel: nil
            ),
        ],

        // MARK: center — no defaults (all 8 directions are language-specific)

        // MARK: midRight

        GridSlot.midRight: [
            .swipeUpLeft: KeyBinding(
                label: "|", action: .commitText("|"), category: nil,
                returnAction: .commitText("¶"), accessibilityLabel: nil
            ),
            .swipeUp: shiftUp,
            .swipeUpRight: KeyBinding(
                label: "}", action: .commitText("}"), category: nil,
                returnAction: .commitText("{"), accessibilityLabel: nil
            ),
            .swipeRight: KeyBinding(
                label: ")", action: .commitText(")"), category: nil,
                returnAction: .commitText("("), accessibilityLabel: nil
            ),
            .swipeDown: shiftDownHidden,
            .swipeDownRight: KeyBinding(
                label: "]", action: .commitText("]"), category: nil,
                returnAction: .commitText("["), accessibilityLabel: nil
            ),
            .swipeDownLeft: KeyBinding(
                label: "@", action: .commitText("@"), category: nil,
                returnAction: .commitText("ª"), accessibilityLabel: nil
            ),
        ],

        // MARK: bottomLeft

        GridSlot.bottomLeft: [
            .swipeUpLeft: KeyBinding(
                label: "~", action: .compose(trigger: "~"), category: .compose,
                returnAction: .commitText("˜"), accessibilityLabel: nil
            ),
            .swipeUp: KeyBinding(
                label: "¨", action: .compose(trigger: "¨"), category: .compose,
                returnAction: .commitText("˝"), accessibilityLabel: nil
            ),
            .swipeRight: KeyBinding(
                label: "*", action: .compose(trigger: "*"), category: .compose,
                returnAction: .commitText("†"), accessibilityLabel: nil
            ),
            .swipeDownRight: KeyBinding(
                label: "⇥", action: .commitText("\t"), category: nil,
                returnAction: .commitText("\t"), accessibilityLabel: nil
            ),
            .swipeLeft: KeyBinding(
                label: "<", action: .commitText("<"), category: nil,
                returnAction: .commitText("‹"), accessibilityLabel: nil
            ),
        ],

        // MARK: bottomCenter

        GridSlot.bottomCenter: [
            .swipeUpLeft: KeyBinding(
                label: "\"", action: .commitText("\""), category: nil,
                returnAction: .commitText("\u{201C}"), accessibilityLabel: nil
            ),
            .swipeUpRight: KeyBinding(
                label: "'", action: .commitText("'"), category: nil,
                returnAction: .commitText("\u{201D}"), accessibilityLabel: nil
            ),
            .swipeDownRight: KeyBinding(
                label: ":", action: .commitText(":"), category: nil,
                returnAction: .commitText("„"), accessibilityLabel: nil
            ),
            .swipeDown: KeyBinding(
                label: ".", action: .commitText("."), category: nil,
                returnAction: .commitText("…"), accessibilityLabel: nil
            ),
            .swipeDownLeft: KeyBinding(
                label: ",", action: .commitText(","), category: nil,
                returnAction: .commitText(","), accessibilityLabel: nil
            ),
        ],

        // MARK: bottomRight

        GridSlot.bottomRight: [
            .swipeUp: KeyBinding(
                label: "&", action: .commitText("&"), category: nil,
                returnAction: .commitText("§"), accessibilityLabel: nil
            ),
            .swipeUpRight: KeyBinding(
                label: "°", action: .compose(trigger: "°"), category: .compose,
                returnAction: .commitText("º"), accessibilityLabel: nil
            ),
            .swipeRight: KeyBinding(
                label: ">", action: .commitText(">"), category: nil,
                returnAction: .commitText("›"), accessibilityLabel: nil
            ),
            .swipeDownRight: KeyBinding(
                label: "", action: .commitText(" "), category: nil,
                returnAction: .commitText(" "), accessibilityLabel: nil
            ),
            .swipeDownLeft: KeyBinding(
                label: ";", action: .commitText(";"), category: nil,
                returnAction: .commitText(";"), accessibilityLabel: nil
            ),
            .swipeLeft: KeyBinding(
                label: "#", action: .commitText("#"), category: nil,
                returnAction: .commitText("£"), accessibilityLabel: nil
            ),
        ],
    ]
}
