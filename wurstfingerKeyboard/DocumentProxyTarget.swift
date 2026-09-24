//
//  DocumentProxyTarget.swift
//  Wurstfinger
//
//  Thin wrapper conforming to TextInputTarget that delegates to a
//  UITextDocumentProxy. Bridges UIKit's document proxy into the
//  middleware pipeline's protocol-based abstraction.
//

import UIKit

/// Adapts a `UITextDocumentProxy` to the `TextInputTarget` protocol used
/// by the middleware pipeline.
///
/// Holds a weak reference to the owning `UIInputViewController` so it can
/// access `textDocumentProxy` (which may change between input fields) and
/// `hasFullAccess` without extending the controller's lifetime.
final class DocumentProxyTarget: TextInputTarget {
    private weak var controller: UIInputViewController?

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy? {
        controller?.textDocumentProxy
    }

    func insertText(_ text: String) {
        proxy?.insertText(text)
    }

    func deleteBackward() {
        proxy?.deleteBackward()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
    }

    var documentContextBeforeInput: String? {
        proxy?.documentContextBeforeInput
    }

    var documentContextAfterInput: String? {
        proxy?.documentContextAfterInput
    }

    var selectedText: String? {
        proxy?.selectedText
    }

    var hasFullAccess: Bool {
        controller?.hasFullAccess ?? false
    }

    var capitalizationMode: TextCapitalizationMode {
        switch proxy?.autocapitalizationType ?? .sentences {
        case .none: .none
        case .words: .words
        case .allCharacters: .allCharacters
        default: .sentences
        }
    }

    var fieldKind: TextFieldKind {
        guard let proxy else { return .text }
        if proxy.isSecureTextEntry == true {
            return .addressOrPassword
        }
        switch proxy.keyboardType ?? .default {
        case .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad:
            return .number
        case .URL, .emailAddress:
            return .addressOrPassword
        default:
            break
        }
        let addressTypes: Set<UITextContentType> = [.URL, .emailAddress, .username, .password, .newPassword]
        if let contentType = proxy.textContentType ?? nil, addressTypes.contains(contentType) {
            return .addressOrPassword
        }
        return .text
    }

    var isSecureTextEntry: Bool {
        proxy?.isSecureTextEntry == true
    }

    var documentIdentifier: UUID? {
        proxy?.documentIdentifier
    }

    var allowsSpellChecking: Bool {
        guard let proxy, proxy.isSecureTextEntry != true else { return false }

        switch proxy.keyboardType {
        case .default, .asciiCapable, .namePhonePad, .webSearch:
            break
        default:
            return false
        }

        let excludedContentTypes: Set<UITextContentType> = [
            .emailAddress, .URL, .telephoneNumber, .username,
            .password, .newPassword, .oneTimeCode, .creditCardNumber,
        ]
        let resolvedContentType = proxy.textContentType ?? nil
        if let contentType = resolvedContentType,
           excludedContentTypes.contains(contentType) {
            return false
        }
        return true
    }
}
