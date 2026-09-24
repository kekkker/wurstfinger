//
//  TextInputTarget.swift
//  Wurstfinger
//
//  Protocol abstracting text-input operations for the middleware pipeline.
//

import Foundation

/// How the focused field wants its text capitalized (mirrors
/// `UITextAutocapitalizationType` without importing UIKit).
enum TextCapitalizationMode: Equatable {
    case none
    case words
    case sentences
    case allCharacters
}

/// Broad kind of the focused field, used to pick the starting layer and to
/// keep auto-capitalization out of addresses and passwords.
enum TextFieldKind: Equatable {
    case text
    /// Number, decimal and phone pads: start on the numeric layer.
    case number
    /// URL, email and password fields: never auto-capitalize.
    case addressOrPassword
}

/// Minimal protocol for the text-input operations the middleware pipeline
/// performs. A thin wrapper around `UITextDocumentProxy` (declared in the
/// keyboard extension target where UIKit is available) conforms to this
/// protocol at pipeline construction time.
///
/// Using a dedicated protocol keeps the middleware testable without the
/// full `UITextDocumentProxy` contract (which has dozens of required
/// members from `UIKeyInput` and `UITextInputTraits`).
protocol TextInputTarget: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)

    /// Text immediately before the cursor (up to the current paragraph start).
    /// Required for lookback-based composition (e.g. Vietnamese Telex digraphs).
    /// `nil` when no context is available yet.
    var documentContextBeforeInput: String? { get }

    /// Text immediately after the cursor (up to the current paragraph end).
    /// Required for delete-forward and word-boundary movement.
    var documentContextAfterInput: String? { get }

    /// Currently selected text, if any.
    var selectedText: String? { get }

    /// Whether Full Access (Open Access) is enabled for the keyboard.
    /// Clipboard operations require this.
    var hasFullAccess: Bool { get }

    /// Whether the current input traits are appropriate for spell checking.
    var allowsSpellChecking: Bool { get }

    /// The focused field's capitalization preference.
    var capitalizationMode: TextCapitalizationMode { get }

    /// The focused field's broad kind.
    var fieldKind: TextFieldKind { get }

    /// Whether the focused field hides its text (passwords).
    var isSecureTextEntry: Bool { get }

    /// Identifies the focused document; changes when focus moves to another field.
    var documentIdentifier: UUID? { get }
}

extension TextInputTarget {
    var allowsSpellChecking: Bool {
        true
    }

    var capitalizationMode: TextCapitalizationMode {
        .sentences
    }

    var fieldKind: TextFieldKind {
        .text
    }

    var isSecureTextEntry: Bool {
        false
    }

    var documentIdentifier: UUID? {
        nil
    }
}
