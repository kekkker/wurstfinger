//
//  AdvancedTextMiddleware.swift
//  Wurstfinger
//
//  Handles text actions that require more than a simple proxy call:
//  delete-forward, capitalize-word, word-cursor movement, and clipboard.
//

import UIKit

/// Handles advanced text-input actions that `TextInputMiddleware` leaves
/// as pass-through: delete-forward, capitalize-word, word-boundary cursor
/// movement, and clipboard (copy/paste/cut).
///
/// These actions need multi-step proxy interaction (e.g. read context,
/// delete, re-insert) and are therefore separated from the basic middleware
/// to keep each middleware focused and independently testable.
struct AdvancedTextMiddleware: ActionMiddleware {
    private let targetProvider: () -> TextInputTarget?
    private let localeProvider: () -> Locale

    init(target: @escaping () -> TextInputTarget?, locale: @escaping () -> Locale) {
        targetProvider = target
        localeProvider = locale
    }

    func process(_ context: ActionContext, next: (ActionContext) -> Void) {
        if let target = targetProvider() {
            apply(action: context.action, to: target)
        }
        next(context)
    }

    private func apply(action: KeyAction, to target: TextInputTarget) {
        switch action {
        case .deleteForward:
            deleteForward(target: target)
        case let .capitalizeWord(uppercased):
            capitalizeWord(target: target, uppercased: uppercased)
        case .copy:
            handleCopy(target: target)
        case .paste:
            handlePaste(target: target)
        case .cut:
            handleCut(target: target)
        case .copyAll:
            handleCopyAll(target: target)
        case .cutAll:
            handleCutAll(target: target)
        case .deleteWord:
            handleDeleteWord(target: target)
        default:
            break
        }
    }

    // MARK: - Whole-message editing (Thumb-Key style)

    /// Reads the entire document context around the cursor.
    private func wholeMessage(target: TextInputTarget) -> (before: String, after: String) {
        (target.documentContextBeforeInput ?? "", target.documentContextAfterInput ?? "")
    }

    private func handleCopyAll(target: TextInputTarget) {
        guard target.hasFullAccess else { return }
        let (before, after) = wholeMessage(target: target)
        let all = before + after
        guard !all.isEmpty else { return }
        UIPasteboard.general.string = all
    }

    private func handleCutAll(target: TextInputTarget) {
        let (before, after) = wholeMessage(target: target)
        let all = before + after
        guard !all.isEmpty else { return }
        if target.hasFullAccess {
            UIPasteboard.general.string = all
        }
        // Move past any trailing text, deleting it, then delete everything
        // before the cursor.
        for _ in 0 ..< after.count {
            target.adjustTextPosition(byCharacterOffset: 1)
            target.deleteBackward()
        }
        for _ in 0 ..< before.count {
            target.deleteBackward()
        }
    }

    private func handleDeleteWord(target: TextInputTarget) {
        guard let context = target.documentContextBeforeInput, !context.isEmpty else { return }
        // Delete any whitespace adjacent to the cursor, then the word before it.
        var deleteCount = 0
        var sawWord = false
        for character in context.reversed() {
            if character.isWhitespace, !sawWord {
                deleteCount += 1 // trailing whitespace right at the cursor
            } else if !character.isWhitespace {
                sawWord = true
                deleteCount += 1
            } else {
                break // whitespace before the word — stop
            }
        }
        guard deleteCount > 0 else { return }
        for _ in 0 ..< deleteCount {
            target.deleteBackward()
        }
    }

    // MARK: - Delete Forward

    private func deleteForward(target: TextInputTarget) {
        guard let after = target.documentContextAfterInput, !after.isEmpty else { return }
        target.adjustTextPosition(byCharacterOffset: 1)
        target.deleteBackward()
    }

    // MARK: - Capitalize Word

    private func capitalizeWord(target: TextInputTarget, uppercased: Bool) {
        guard let context = target.documentContextBeforeInput, !context.isEmpty else { return }

        var characters: [Character] = []
        for character in context.reversed() {
            if character.isLetter {
                characters.append(character)
            } else {
                break
            }
        }
        guard !characters.isEmpty else { return }

        let word = String(characters.reversed())
        let locale = localeProvider()
        let transformed = uppercased ? word.uppercased(with: locale) : word.lowercased(with: locale)

        for _ in 0 ..< word.count {
            target.deleteBackward()
        }
        target.insertText(transformed)
    }

    // MARK: - Clipboard

    private func handleCopy(target: TextInputTarget) {
        guard target.hasFullAccess else { return }
        if let selected = target.selectedText, !selected.isEmpty {
            UIPasteboard.general.string = selected
        }
    }

    private func handlePaste(target: TextInputTarget) {
        guard target.hasFullAccess else { return }
        if let text = UIPasteboard.general.string, !text.isEmpty {
            target.insertText(text)
        }
    }

    private func handleCut(target: TextInputTarget) {
        guard target.hasFullAccess else { return }
        if let selected = target.selectedText, !selected.isEmpty {
            UIPasteboard.general.string = selected
            target.deleteBackward()
        }
    }
}
