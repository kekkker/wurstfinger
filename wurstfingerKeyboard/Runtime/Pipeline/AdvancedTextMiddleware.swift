//
//  AdvancedTextMiddleware.swift
//  Wurstfinger
//
//  Handles text actions that need more than a single proxy call: word and
//  line navigation, word deletion, capitalization, clipboard, and the
//  selection/history commands that go through the WurstSecure text bridge.
//

import Foundation

/// Word boundaries as Thumb-Key finds them (`deleteWordBeforeCursor` and
/// friends in `Utils.kt`), using Unicode-aware word characters.
enum WordBoundary {
    // swiftlint:disable force_try
    private static let beforeCursor = try! NSRegularExpression(pattern: #"(\w+\W?|[^\s\w]+)?\s*$"#)
    private static let afterCursor = try! NSRegularExpression(pattern: #"^\s?(\w+\W?|[^\s\w]+|\s+)"#)
    // swiftlint:enable force_try

    /// Characters between the cursor and the start of the previous word.
    static func lengthBeforeCursor(in text: String) -> Int {
        matchLength(of: beforeCursor, in: text)
    }

    /// Characters between the cursor and the end of the next word.
    static func lengthAfterCursor(in text: String) -> Int {
        matchLength(of: afterCursor, in: text)
    }

    private static func matchLength(of regex: NSRegularExpression, in text: String) -> Int {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matched = Range(match.range, in: text)
        else { return 0 }
        return text[matched].count
    }
}

/// Handles advanced text-input actions that `TextInputMiddleware` leaves
/// as pass-through.
///
/// These actions need multi-step proxy interaction (read context, delete,
/// re-insert) or the host-side text bridge, and are therefore separated from
/// the basic middleware to keep each one focused and independently testable.
struct AdvancedTextMiddleware: ActionMiddleware {
    /// Delay between a bridged select-all and reading the selection back,
    /// matching Thumb-Key's wait before cutting or copying everything.
    static let selectAllSettleDelay: TimeInterval = 0.1
    /// Delay between steps when walking to a line or text boundary.
    static let boundaryStepDelay: TimeInterval = 0.05
    /// Upper bound on boundary steps, so a host that never updates its
    /// context cannot keep the cursor moving.
    static let maxBoundarySteps = 40

    private let targetProvider: () -> TextInputTarget?
    private let localeProvider: () -> Locale
    private let bridgeProvider: () -> TextCommandBridge?
    private let clipboardProvider: () -> ClipboardService?
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(
        target: @escaping () -> TextInputTarget?,
        locale: @escaping () -> Locale,
        bridge: @escaping () -> TextCommandBridge? = { nil },
        clipboard: @escaping () -> ClipboardService? = { nil },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        targetProvider = target
        localeProvider = locale
        bridgeProvider = bridge
        clipboardProvider = clipboard
        self.schedule = schedule
    }

    func process(_ context: ActionContext, next: (ActionContext) -> Void) {
        if let target = targetProvider() {
            apply(action: context.action, to: target)
        }
        next(context)
    }

    private var bridge: TextCommandBridge? {
        bridgeProvider().flatMap { $0.isAvailable ? $0 : nil }
    }

    private func apply(action: KeyAction, to target: TextInputTarget) {
        switch action {
        case .deleteForward, .deleteWordBackward, .deleteWordForward, .moveWordBackward, .moveWordForward:
            applyWordEdit(action, target: target)
        case .cursorToLineStart, .cursorToLineEnd, .cursorToTextStart, .cursorToTextEnd:
            moveToBoundary(action, target: target)
        case let .toggleWordCapitalization(up):
            toggleWordCapitalization(up: up, target: target)
        case .copy, .cut, .paste:
            applyClipboard(action, target: target)
        case .selectAll:
            bridge?.send(.selectAll)
        case .selectLine:
            selectLine(target: target)
        case .undo:
            bridge?.send(.undo)
        case .redo:
            bridge?.send(.redo)
        default:
            break
        }
    }

    private func applyWordEdit(_ action: KeyAction, target: TextInputTarget) {
        let before = target.documentContextBeforeInput ?? ""
        let after = target.documentContextAfterInput ?? ""
        switch action {
        case .deleteForward:
            deleteForward(count: 1, target: target)
        case .deleteWordBackward:
            for _ in 0 ..< WordBoundary.lengthBeforeCursor(in: before) {
                target.deleteBackward()
            }
        case .deleteWordForward:
            deleteForward(count: WordBoundary.lengthAfterCursor(in: after), target: target)
        case .moveWordBackward:
            let count = WordBoundary.lengthBeforeCursor(in: before)
            if count > 0 {
                target.adjustTextPosition(byCharacterOffset: -count)
            }
        case .moveWordForward:
            let count = WordBoundary.lengthAfterCursor(in: after)
            if count > 0 {
                target.adjustTextPosition(byCharacterOffset: count)
            }
        default:
            break
        }
    }

    private func applyClipboard(_ action: KeyAction, target: TextInputTarget) {
        switch action {
        case .copy:
            copyOrCut(cut: false, target: target)
        case .cut:
            copyOrCut(cut: true, target: target)
        default:
            if target.hasFullAccess, let text = clipboardProvider()?.textToPaste(), !text.isEmpty {
                target.insertText(text)
            }
        }
    }

    // MARK: - Deletion

    private func deleteForward(count: Int, target: TextInputTarget) {
        let available = target.documentContextAfterInput?.count ?? 0
        let count = min(count, available)
        guard count > 0 else { return }
        target.adjustTextPosition(byCharacterOffset: count)
        for _ in 0 ..< count {
            target.deleteBackward()
        }
    }

    // MARK: - Line and Text Boundaries

    private func moveToBoundary(_ action: KeyAction, target: TextInputTarget) {
        if let bridge {
            switch action {
            case .cursorToLineStart: bridge.send(.moveToLineStart)
            case .cursorToLineEnd: bridge.send(.moveToLineEnd)
            case .cursorToTextStart: bridge.send(.moveToDocumentStart)
            default: bridge.send(.moveToDocumentEnd)
            }
            return
        }
        let forward = action == .cursorToLineEnd || action == .cursorToTextEnd
        let stopsAtNewline = action == .cursorToLineStart || action == .cursorToLineEnd
        stepToBoundary(
            forward: forward, stopsAtNewline: stopsAtNewline,
            target: target, previousContext: nil, remainingSteps: Self.maxBoundarySteps
        )
    }

    /// Walks the cursor using only the document context, which apps may
    /// truncate: each step moves across the visible context, then re-reads it.
    private func stepToBoundary(
        forward: Bool,
        stopsAtNewline: Bool,
        target: TextInputTarget,
        previousContext: String?,
        remainingSteps: Int
    ) {
        let context = (forward ? target.documentContextAfterInput : target.documentContextBeforeInput) ?? ""
        guard !context.isEmpty, context != previousContext, remainingSteps > 0 else { return }

        var distance = context.count
        var reachedNewline = false
        if stopsAtNewline {
            if forward, let newline = context.firstIndex(where: \.isNewline) {
                distance = context.distance(from: context.startIndex, to: newline)
                reachedNewline = true
            } else if !forward, let newline = context.lastIndex(where: \.isNewline) {
                distance = context.distance(from: context.index(after: newline), to: context.endIndex)
                reachedNewline = true
            }
        }
        if distance > 0 {
            target.adjustTextPosition(byCharacterOffset: forward ? distance : -distance)
        }
        guard !reachedNewline, distance > 0 else { return }
        schedule(Self.boundaryStepDelay) { [weak target] in
            guard let target else { return }
            stepToBoundary(
                forward: forward, stopsAtNewline: stopsAtNewline,
                target: target, previousContext: context, remainingSteps: remainingSteps - 1
            )
        }
    }

    private func selectLine(target: TextInputTarget) {
        guard let bridge else { return }
        let before = target.documentContextBeforeInput ?? ""
        let after = target.documentContextAfterInput ?? ""
        let lineStart = before.lastIndex(where: \.isNewline).map { before.index(after: $0) } ?? before.startIndex
        let backward = before.distance(from: lineStart, to: before.endIndex)
        let forward = after.firstIndex(where: \.isNewline).map { after.distance(from: after.startIndex, to: $0) + 1 }
            ?? after.count
        bridge.send(.selectRelative(start: -backward, length: backward + forward))
    }

    // MARK: - Capitalization

    /// Characters that end a word for capitalization, from Thumb-Key.
    private static let wordBorderCharacters = Set(".,;:!?\"'()-—[]{}<>/\\|#$%^_+=~`")

    private func toggleWordCapitalization(up: Bool, target: TextInputTarget) {
        guard let context = target.documentContextBeforeInput, !context.isEmpty else { return }
        let text = String(context.suffix(100))
        let wordStart = text.lastIndex { $0.isWhitespace || Self.wordBorderCharacters.contains($0) }
            .map { text.index(after: $0) } ?? text.startIndex
        guard wordStart < text.endIndex else { return }

        let word = String(text[wordStart...])
        let locale = localeProvider()
        let replacement: String = if up {
            if word.first?.isUppercase == true {
                word.uppercased(with: locale)
            } else {
                String(word.prefix(1)).uppercased(with: locale) + word.dropFirst()
            }
        } else {
            word.lowercased(with: locale)
        }
        guard replacement != word else { return }
        for _ in 0 ..< word.count {
            target.deleteBackward()
        }
        target.insertText(replacement)
    }

    // MARK: - Clipboard

    /// Copies or cuts the selection. With nothing selected, acts on the whole
    /// text: select-all through the bridge when available, otherwise the
    /// document context around the cursor.
    private func copyOrCut(cut: Bool, target: TextInputTarget) {
        guard target.hasFullAccess, let clipboard = clipboardProvider() else { return }

        if let selected = target.selectedText, !selected.isEmpty {
            clipboard.copy(selected)
            if cut {
                target.deleteBackward()
            }
            return
        }

        if let bridge {
            bridge.send(.selectAll)
            schedule(Self.selectAllSettleDelay) { [weak target] in
                guard let target else { return }
                if let selected = target.selectedText, !selected.isEmpty {
                    clipboard.copy(selected)
                    if cut {
                        target.deleteBackward()
                    }
                } else {
                    copyOrCutWholeContext(cut: cut, target: target, clipboard: clipboard)
                }
            }
            return
        }
        copyOrCutWholeContext(cut: cut, target: target, clipboard: clipboard)
    }

    private func copyOrCutWholeContext(cut: Bool, target: TextInputTarget, clipboard: ClipboardService) {
        let before = target.documentContextBeforeInput ?? ""
        let after = target.documentContextAfterInput ?? ""
        let all = before + after
        guard !all.isEmpty else { return }
        clipboard.copy(all)
        guard cut else { return }
        deleteForward(count: after.count, target: target)
        for _ in 0 ..< before.count {
            target.deleteBackward()
        }
    }
}
