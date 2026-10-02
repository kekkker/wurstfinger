//
//  TextCommandBridge.swift
//  Wurstfinger
//
//  Editing commands a keyboard extension cannot perform through
//  UITextDocumentProxy (select all, undo, redo, selections). On jailbroken
//  devices the WurstSecure tweak runs them inside the host app.
//

import Foundation
import notify

/// An editing command executed by the host app's text input.
enum TextCommand: Equatable {
    case selectAll
    case undo
    case redo
    /// Remember the cursor as the anchor of a new selection.
    case beginSelection
    /// Select from the anchor to `anchor + offset`.
    case extendSelection(Int)
    /// Collapse the selection onto its start or end.
    case collapseSelection(toEnd: Bool)
    /// Select `length` characters starting `start` characters from the cursor.
    case selectRelative(start: Int, length: Int)
    case moveToLineStart
    case moveToLineEnd
    case moveToDocumentStart
    case moveToDocumentEnd

    /// Wire format shared with the tweak: bits 0–7 opcode, 8–15 sequence,
    /// 16–39 first argument, 40–63 second argument (both 24-bit two's complement).
    func payload(sequence: UInt8) -> UInt64 {
        let (opcode, first, second): (UInt64, Int, Int) = switch self {
        case .selectAll: (1, 0, 0)
        case .undo: (2, 0, 0)
        case .redo: (3, 0, 0)
        case .beginSelection: (4, 0, 0)
        case let .extendSelection(offset): (5, offset, 0)
        case let .collapseSelection(toEnd): (6, toEnd ? 1 : 0, 0)
        case let .selectRelative(start, length): (7, start, length)
        case .moveToLineStart: (8, 0, 0)
        case .moveToLineEnd: (9, 0, 0)
        case .moveToDocumentStart: (10, 0, 0)
        case .moveToDocumentEnd: (11, 0, 0)
        }
        return opcode
            | UInt64(sequence) << 8
            | Self.encode24(first) << 16
            | Self.encode24(second) << 40
    }

    private static func encode24(_ value: Int) -> UInt64 {
        let clamped = min(max(value, -0x800000), 0x7FFFFF)
        return UInt64(bitPattern: Int64(clamped)) & 0xFFFFFF
    }
}

/// Sends `TextCommand`s to the host app.
protocol TextCommandBridge: AnyObject {
    /// Whether a host-side receiver is installed.
    var isAvailable: Bool { get }
    func send(_ command: TextCommand)
}

/// Posts commands as a Darwin notification carrying the payload in its state.
final class DarwinTextCommandBridge: TextCommandBridge {
    static let notificationName = "de.akator.wurstfinger.text-command.v1"
    /// Set by WurstSecure when it loads into the keyboard extension.
    static let presenceVariable = "WURSTSECURE_TEXT_BRIDGE"

    let isAvailable: Bool
    private var token: Int32 = -1
    private var sequence: UInt8 = 0

    init() {
        isAvailable = ProcessInfo.processInfo.environment[Self.presenceVariable] == "1"
        guard isAvailable else { return }
        if notify_register_check(Self.notificationName, &token) != UInt32(NOTIFY_STATUS_OK) {
            token = -1
        }
    }

    deinit {
        if token >= 0 {
            notify_cancel(token)
        }
    }

    func send(_ command: TextCommand) {
        guard isAvailable, token >= 0 else { return }
        sequence &+= 1
        notify_set_state(token, command.payload(sequence: sequence))
        notify_post(Self.notificationName)
    }
}
