//
//  KeyModifications.swift
//  Wurstfinger
//
//  Thumb-Key's "Modify keys": YAML that changes individual keys of a
//  layout. Same format as Thumb-Key, so existing configs carry over:
//
//      ENThumbKey:
//        main:
//          key1_0:
//            center: { text: ñ }
//
//  Keys are addressed as key{row}_{column} in the portrait arrangement.
//

import Foundation

struct KeyModificationError: Error, Equatable, CustomStringConvertible {
    let description: String
}

enum KeyModifications {
    /// Thumb-Key layout names for the layouts ported 1:1.
    static let thumbKeyLayoutNames: [String: String] = [
        "ENThumbKey": "en_US_thumbkey",
        "RUThumbKey": "ru_RU_thumbkey",
    ]

    /// Applies the modifications for `definition`, if any. Throws on
    /// malformed YAML or invalid modifications.
    static func apply(_ yaml: String, to definition: KeyboardDefinition) throws -> KeyboardDefinition {
        guard let layouts = try parse(yaml) else { return definition }
        var result = definition
        for (name, modes) in layouts where layoutId(for: name) == definition.id {
            result = try modify(result, with: modes, layoutName: name)
        }
        return result
    }

    /// Checks every layout in `yaml` against the registry.
    static func validate(_ yaml: String) throws {
        guard let layouts = try parse(yaml) else { return }
        for (name, modes) in layouts {
            guard let id = layoutId(for: name), let definition = KeyboardRegistry.load(id: id) else {
                throw KeyModificationError(description: String(localized: "Unknown layout \"\(name)\"."))
            }
            _ = try modify(definition, with: modes, layoutName: name)
        }
    }

    // MARK: - Parsing

    private static func parse(_ yaml: String) throws -> [(key: String, value: YAMLNode)]? {
        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let root: YAMLNode
        do {
            root = try YAMLMapping.parse(yaml)
        } catch let error as YAMLError {
            throw KeyModificationError(description: error.description)
        }
        // Top-level "x-" keys hold shared anchors, as in Thumb-Key.
        return root.entries?.filter { !$0.key.hasPrefix("x-") }
    }

    private static func layoutId(for name: String) -> String? {
        if let id = thumbKeyLayoutNames[name] {
            return id
        }
        return KeyboardRegistry.load(id: name) != nil ? name : nil
    }

    // MARK: - Applying

    private static func modify(_ definition: KeyboardDefinition, with modes: YAMLNode, layoutName: String) throws -> KeyboardDefinition {
        guard let entries = modes.entries else {
            throw KeyModificationError(description: String(localized: "\(layoutName) must contain modes like main or numeric."))
        }
        var result = definition
        for (modeName, keys) in entries {
            let targets: [String]
            switch modeName {
            case "main": targets = [ModeNames.main]
            case "shifted": targets = [ModeNames.shifted, ModeNames.capsLock]
            case "numeric": targets = [ModeNames.numeric]
            case "ctrled", "alted", "emoji": continue
            default:
                throw KeyModificationError(description: String(localized: "Unknown mode \"\(modeName)\"."))
            }
            for target in targets {
                guard let mode = result.mode(target) else { continue }
                result = try result.replacingMode(target, with: modify(mode, with: keys, path: "\(layoutName).\(modeName)"))
            }
        }
        return result
    }

    private static func modify(_ mode: KeyboardMode, with keys: YAMLNode, path: String) throws -> KeyboardMode {
        guard let entries = keys.entries, let portrait = mode.arrangement(for: .portrait) else {
            throw KeyModificationError(description: String(localized: "\(path) must contain keys like key0_0."))
        }
        var updatedKeys = mode.keys
        var rows = portrait.rows
        for (name, changes) in entries {
            guard let (row, column) = position(from: name), row < rows.count, column < rows[row].count else {
                throw KeyModificationError(description: String(localized: "\(path) has no key \(name)."))
            }
            let placement = rows[row][column]
            guard let key = updatedKeys[placement.keyId] else { continue }
            let (modified, width) = try modify(key, with: changes, path: "\(path).\(name)")
            updatedKeys[placement.keyId] = modified
            if let width {
                rows[row][column] = KeyPlacement(keyId: placement.keyId, widthMultiplier: width, heightMultiplier: placement.heightMultiplier)
            }
        }
        for (index, row) in rows.enumerated() where row.reduce(0, { $0 + $1.widthMultiplier }) != portrait.columns {
            throw KeyModificationError(description: String(localized: "Row \(index) of \(path) must be \(portrait.columns) keys wide."))
        }
        var arrangements = mode.arrangements
        let newPortrait = GridArrangement(columns: portrait.columns, rows: rows)
        if newPortrait != portrait {
            arrangements[.portrait] = newPortrait
            arrangements[.portraitUtilityLeft] = newPortrait.mirroredHorizontally()
        }
        return KeyboardMode(
            name: mode.name, keys: updatedKeys, arrangements: arrangements,
            autoTransitions: mode.autoTransitions, doubleTapMode: mode.doubleTapMode
        )
    }

    private static func position(from name: String) -> (Int, Int)? {
        guard name.hasPrefix("key") else { return nil }
        let parts = name.dropFirst(3).split(separator: "_")
        guard parts.count == 2, let row = Int(parts[0]), let column = Int(parts[1]) else { return nil }
        return (row, column)
    }

    private static let directions: [String: GestureType] = [
        "center": .tap, "left": .swipeLeft, "topLeft": .swipeUpLeft, "top": .swipeUp,
        "topRight": .swipeUpRight, "right": .swipeRight, "bottomRight": .swipeDownRight,
        "bottom": .swipeDown, "bottomLeft": .swipeDownLeft, "longPress": .longPress,
    ]

    private static let swipeTypes: [String: SwipeMode] = [
        "EIGHT_WAY": .eightWay, "FOUR_WAY_CROSS": .fourWayCross, "FOUR_WAY_DIAGONAL": .fourWayDiagonal,
        "TWO_WAY_HORIZONTAL": .twoWayHorizontal, "TWO_WAY_VERTICAL": .twoWayVertical,
    ]

    private static let slideTypes: [String: SlideType] = [
        "NONE": .none, "MOVE_CURSOR": .moveCursor, "DELETE": .delete,
    ]

    private static func modify(_ key: KeyConfig, with changes: YAMLNode, path: String) throws -> (KeyConfig, Int?) {
        guard let entries = changes.entries else {
            throw KeyModificationError(description: String(localized: "\(path) must be a mapping."))
        }
        var bindings = key.bindings
        var swipeMode = key.swipeMode
        var slideType = key.slideType
        var style = key.style
        var width: Int?

        for (property, value) in entries {
            let location = "\(path).\(property)"
            if let gesture = directions[property] {
                if let binding = try modify(bindings[gesture], with: value, path: location, isTap: gesture == .tap) {
                    bindings[gesture] = binding
                } else {
                    bindings.removeValue(forKey: gesture)
                }
                continue
            }
            let scalar = value.scalar ?? ""
            switch property {
            case "swipeType":
                swipeMode = try lookup(scalar, in: swipeTypes, path: location)
            case "slideType":
                slideType = try lookup(scalar, in: slideTypes, path: location)
            case "backgroundColor":
                switch scalar {
                case "SURFACE": style = key.style == .spacebar ? .spacebar : .primary
                case "SURFACE_VARIANT": style = key.style == .spacebar ? .spacebar : .utility
                default: throw invalidValue(scalar, path: location)
                }
            case "widthMultiplier":
                guard let multiplier = Int(scalar), multiplier > 0 else { throw invalidValue(scalar, path: location) }
                width = multiplier
            default:
                throw KeyModificationError(description: String(localized: "Unknown property \(location)."))
            }
        }

        let modified = KeyConfig(
            id: key.id, bindings: bindings, swipeMode: swipeMode,
            slideType: slideType, style: style, tapCycleActions: key.tapCycleActions
        )
        return (modified, width)
    }

    private static let bindingProperties: Set<String> = [
        "text", "displayText", "size", "color", "remove", "keyAction", "swipeReturnText", "swipeReturnAction",
    ]

    /// Thumb-Key's `modifyKeyC`: returns the new binding, or nil to remove it.
    /// A removed center becomes a no-op.
    private static func modify(_ binding: KeyBinding?, with change: YAMLNode, path: String, isTap: Bool) throws -> KeyBinding? {
        let values = try bindingValues(change, path: path)
        let keyAction = try values["keyAction"].map { try commonBinding(for: $0, path: "\(path).keyAction") }
        let returnAction = try values["swipeReturnAction"].map { try commonBinding(for: $0, path: "\(path).swipeReturnAction") }
        if values["remove"] == "true" {
            return isTap ? CommonKeys.hiddenBinding(.none) : nil
        }

        var result = binding ?? CommonKeys.hiddenBinding(.none)
        if let text = values["text"] {
            result = KeyBinding(label: text, action: .commitText(text), category: nil, returnAction: result.returnAction, accessibilityLabel: nil)
        }
        if let keyAction {
            result = keyAction
        }
        if let text = values["swipeReturnText"] {
            result = result.with(returnAction: .commitText(text))
        }
        if let returnAction {
            result = result.with(returnAction: returnAction.action)
        }
        if let displayText = values["displayText"] {
            result = result.with(label: displayText, legend: nil)
        }
        if let color = values["color"] {
            result = try result.with(label: result.label, legend: legend(for: color, current: result.legend, path: "\(path).color"))
        }
        return result
    }

    /// The scalar properties of one direction, checked like Thumb-Key does.
    private static func bindingValues(_ change: YAMLNode, path: String) throws -> [String: String] {
        guard let entries = change.entries else {
            throw KeyModificationError(description: String(localized: "\(path) must be a mapping."))
        }
        var values: [String: String] = [:]
        for (property, value) in entries {
            guard bindingProperties.contains(property) else {
                let location = "\(path).\(property)"
                throw KeyModificationError(description: String(localized: "Unknown property \(location)."))
            }
            values[property] = value.scalar ?? ""
        }
        if values["text"] != nil, values["keyAction"] != nil {
            throw KeyModificationError(description: String(localized: "\(path): text and keyAction cannot both be used."))
        }
        if values["swipeReturnText"] != nil, values["swipeReturnAction"] != nil {
            throw KeyModificationError(description: String(localized: "\(path): swipeReturnText and swipeReturnAction cannot both be used."))
        }
        if let size = values["size"], !["LARGE", "MEDIUM", "SMALL", "SMALLEST"].contains(size) {
            throw invalidValue(size, path: "\(path).size")
        }
        return values
    }

    /// Thumb-Key legend colors: MUTED dims the legend, the others are the default.
    private static func legend(for color: String, current: KeyLegend?, path: String) throws -> KeyLegend? {
        switch color {
        case "MUTED": .muted
        case "PRIMARY", "SECONDARY", "SURFACE", "SURFACE_VARIANT": current == .muted ? nil : current
        default: throw invalidValue(color, path: path)
        }
    }

    /// The binding each Thumb-Key `keyAction` stands for, with its legend and
    /// swipe-return action.
    private static let commonBindings: [String: KeyBinding] = {
        let text = CommonKeys.textEditSwipes
        let emoji = CommonKeys.globe.bindings
        let hidden = CommonKeys.hiddenBinding
        let abc = KeyBinding(
            label: NumericLayouts.defaultBackToAlphaLabel, action: .switchMode(ModeNames.main),
            category: .utility, returnAction: nil, accessibilityLabel: nil
        )
        let table: [String: KeyBinding?] = [
            "ToggleNumericMode": CommonKeys.symbols.bindings[.tap],
            "ToggleABCMode": abc,
            "ToggleEmojiMode": emoji[.tap],
            "ToggleClipboardMode": CommonKeys.iconBinding(.openClipboardHistory, icon: "list.clipboard"),
            "ToggleCapsLock": CommonKeys.capsLockToggle,
            "ToggleShiftModeTrue": CommonKeys.shiftUp,
            "ToggleShiftModeFalse": CommonKeys.shiftDown,
            "Left": hidden(.moveCursor(offset: -1), nil),
            "Right": hidden(.moveCursor(offset: 1), nil),
            "Top": hidden(.cursorToLineStart, .cursorToTextStart),
            "Bottom": hidden(.cursorToLineEnd, .cursorToTextEnd),
            "IMEComplete": CommonKeys.return.bindings[.tap],
            "PreviousWordBeforeCursor": hidden(.moveWordBackward, nil),
            "NextWordAfterCursor": hidden(.moveWordForward, nil),
            "GotoSettings": emoji[.swipeUp],
            "SelectAll": text[.swipeUpLeft],
            "Cut": text[.swipeUpRight],
            "Copy": text[.swipeUp],
            "Paste": text[.swipeDown],
            "Undo": text[.swipeDownLeft],
            "Redo": text[.swipeDownRight],
            "Delete": CommonKeys.delete.bindings[.tap],
            "DeleteViaTextManipulation": CommonKeys.delete.bindings[.tap],
            "DeleteCharacterAfterCursor": hidden(.deleteForward, nil),
            "DeleteWordBeforeCursor": hidden(.deleteWordBackward, nil),
            "DeleteWordAfterCursor": hidden(.deleteWordForward, nil),
            "SwitchLanguage": emoji[.swipeLeft],
            "SwitchIME": emoji[.swipeDown],
            "HideKeyboard": emoji[.swipeDownLeft],
            "Noop": hidden(.none, nil),
            // No iOS equivalent: voice input, Ctrl and Alt layers.
            "SwitchIMEVoice": hidden(.none, nil),
            "ToggleCtrlModeTrue": hidden(.none, nil),
            "ToggleCtrlModeFalse": hidden(.none, nil),
            "ToggleAltModeTrue": hidden(.none, nil),
            "ToggleAltModeFalse": hidden(.none, nil),
        ]
        return table.compactMapValues { $0 }
    }()

    private static func commonBinding(for name: String, path: String) throws -> KeyBinding {
        guard let binding = commonBindings[name] else { throw invalidValue(name, path: path) }
        return binding
    }

    private static func lookup<T>(_ value: String, in table: [String: T], path: String) throws -> T {
        guard let result = table[value] else { throw invalidValue(value, path: path) }
        return result
    }

    private static func invalidValue(_ value: String, path: String) -> KeyModificationError {
        KeyModificationError(description: String(localized: "\"\(value)\" is not a valid value for \(path)."))
    }
}
