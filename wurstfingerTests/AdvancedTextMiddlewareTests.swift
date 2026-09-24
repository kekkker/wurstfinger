//
//  AdvancedTextMiddlewareTests.swift
//  WurstfingerTests
//
//  Tests for AdvancedTextMiddleware: word and line editing, capitalization,
//  clipboard, and the bridged selection/history commands. These handlers
//  perform multi-step proxy interaction and are driven here through
//  MockTextTarget.
//

import Foundation
import Testing
@testable import WurstfingerApp

// MARK: - Helpers

/// Records copies and serves a fixed paste text.
private final class MockClipboard: ClipboardService {
    var copied: [String] = []
    var pasteText: String?

    func copy(_ text: String) {
        copied.append(text)
    }

    func textToPaste() -> String? {
        pasteText
    }
}

/// Bridge that simulates the host selecting everything on select-all.
private final class SelectingBridge: TextCommandBridge {
    let isAvailable = true
    var sent: [TextCommand] = []
    weak var target: MockTextTarget?

    func send(_ command: TextCommand) {
        sent.append(command)
        if command == .selectAll, let target {
            target.selectedText = (target.documentContextBeforeInput ?? "") + (target.documentContextAfterInput ?? "")
        }
    }
}

private enum AdvancedTextFixtures {
    static func context(_ action: KeyAction, mode: String = "main") -> ActionContext {
        ActionContext(action: action, binding: nil, mode: mode)
    }

    /// Builds a middleware bound to `target`, running delayed work immediately.
    static func middleware(
        target: MockTextTarget,
        localeId: String = "de_DE",
        bridge: TextCommandBridge? = nil,
        clipboard: ClipboardService? = nil
    ) -> AdvancedTextMiddleware {
        AdvancedTextMiddleware(
            target: { target },
            locale: { Locale(identifier: localeId) },
            bridge: { bridge },
            clipboard: { clipboard },
            schedule: { _, work in work() }
        )
    }

    static func run(_ action: KeyAction, on middleware: AdvancedTextMiddleware) {
        middleware.process(context(action)) { _ in }
    }
}

// MARK: - Process / forwarding

struct AdvancedTextMiddlewareProcessTests {
    @Test func forwardsContextToNext() {
        let target = MockTextTarget()
        let middleware = AdvancedTextFixtures.middleware(target: target)

        var forwarded: ActionContext?
        middleware.process(AdvancedTextFixtures.context(.deleteForward)) { forwarded = $0 }

        #expect(forwarded?.action == .deleteForward)
    }

    @Test func ignoresUnhandledActionsButStillForwards() {
        let target = MockTextTarget()
        target.documentContextBeforeInput = "hallo"
        let middleware = AdvancedTextFixtures.middleware(target: target)

        var forwarded = false
        middleware.process(AdvancedTextFixtures.context(.space)) { _ in forwarded = true }

        #expect(forwarded)
        #expect(target.events.isEmpty)
    }

    @Test func noopWhenTargetUnavailable() {
        let middleware = AdvancedTextMiddleware(target: { nil }, locale: { Locale(identifier: "de_DE") })

        var forwarded = false
        middleware.process(AdvancedTextFixtures.context(.deleteForward)) { _ in forwarded = true }

        #expect(forwarded)
    }
}

// MARK: - Word boundaries

struct WordBoundaryTests {
    @Test func lengthBeforeCursorMatchesThumbKey() {
        #expect(WordBoundary.lengthBeforeCursor(in: "hello world") == 5)
        #expect(WordBoundary.lengthBeforeCursor(in: "hello world  ") == 7, "Trailing spaces go with the word")
        #expect(WordBoundary.lengthBeforeCursor(in: "hello foo.") == 4, "One trailing non-word character")
        #expect(WordBoundary.lengthBeforeCursor(in: "hello ...") == 3, "Punctuation runs count as a word")
        #expect(WordBoundary.lengthBeforeCursor(in: "grüße") == 5, "Non-ASCII letters are word characters")
        #expect(WordBoundary.lengthBeforeCursor(in: "") == 0)
    }

    @Test func lengthAfterCursorMatchesThumbKey() {
        #expect(WordBoundary.lengthAfterCursor(in: " world rest") == 7)
        #expect(WordBoundary.lengthAfterCursor(in: "world") == 5)
        #expect(WordBoundary.lengthAfterCursor(in: "   x") == 3, "A whitespace run counts on its own")
        #expect(WordBoundary.lengthAfterCursor(in: "") == 0)
    }
}

// MARK: - Deletion and movement

struct AdvancedTextMiddlewareEditingTests {
    @Test func deleteForwardRemovesNextCharacter() {
        let target = MockTextTarget()
        target.documentContextAfterInput = "xyz"
        AdvancedTextFixtures.run(.deleteForward, on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.events == [.adjustCursor(1), .deleteBackward])
    }

    @Test func deleteForwardNoopAtEnd() {
        let target = MockTextTarget()
        target.documentContextAfterInput = ""
        AdvancedTextFixtures.run(.deleteForward, on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.events.isEmpty)
    }

    @Test func deleteWordBackwardRemovesPreviousWord() {
        let target = MockTextTarget()
        target.documentContextBeforeInput = "hello world"
        AdvancedTextFixtures.run(.deleteWordBackward, on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.documentContextBeforeInput == "hello ")
        #expect(target.events == Array(repeating: .deleteBackward, count: 5))
    }

    @Test func deleteWordForwardRemovesNextWord() {
        let target = MockTextTarget()
        target.documentContextAfterInput = " world rest"
        AdvancedTextFixtures.run(.deleteWordForward, on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.events == [.adjustCursor(7)] + Array(repeating: .deleteBackward, count: 7))
    }

    @Test func wordMovesUseWordBoundaries() {
        let target = MockTextTarget()
        target.documentContextBeforeInput = "hello world"
        target.documentContextAfterInput = " again"
        let middleware = AdvancedTextFixtures.middleware(target: target)
        AdvancedTextFixtures.run(.moveWordBackward, on: middleware)
        AdvancedTextFixtures.run(.moveWordForward, on: middleware)
        #expect(target.events == [.adjustCursor(-5), .adjustCursor(6)])
    }
}

// MARK: - Line and text boundaries

struct AdvancedTextMiddlewareBoundaryTests {
    @Test func lineStartStopsAtNewline() {
        let target = MockTextTarget()
        target.documentContextBeforeInput = "first\nsecond"
        AdvancedTextFixtures.run(.cursorToLineStart, on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.events == [.adjustCursor(-6)])
    }

    @Test func lineEndStopsAtNewline() {
        let target = MockTextTarget()
        target.documentContextAfterInput = "tail\nnext"
        AdvancedTextFixtures.run(.cursorToLineEnd, on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.events == [.adjustCursor(4)])
    }

    @Test func textStartStopsWhenContextNoLongerChanges() {
        // The mock never updates its context, which is how a host that
        // truncates context looks: one step, then stop instead of looping.
        let target = MockTextTarget()
        target.documentContextBeforeInput = "a\nb"
        AdvancedTextFixtures.run(.cursorToTextStart, on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.events == [.adjustCursor(-3)])
    }

    @Test func bridgeMovesToBoundaries() {
        let target = MockTextTarget()
        let bridge = MockTextCommandBridge()
        let middleware = AdvancedTextFixtures.middleware(target: target, bridge: bridge)
        for action: KeyAction in [.cursorToLineStart, .cursorToLineEnd, .cursorToTextStart, .cursorToTextEnd] {
            AdvancedTextFixtures.run(action, on: middleware)
        }
        #expect(bridge.sent == [.moveToLineStart, .moveToLineEnd, .moveToDocumentStart, .moveToDocumentEnd])
        #expect(target.events.isEmpty)
    }
}

// MARK: - Capitalization

struct AdvancedTextCapitalizationTests {
    private func toggle(_ text: String, up: Bool) -> String? {
        let target = MockTextTarget()
        target.documentContextBeforeInput = text
        AdvancedTextFixtures.run(.toggleWordCapitalization(up: up), on: AdvancedTextFixtures.middleware(target: target))
        return target.documentContextBeforeInput
    }

    @Test func upCapitalizesFirstLetter() {
        #expect(toggle("hello wor", up: true) == "hello Wor")
    }

    @Test func upOnCapitalizedWordUppercasesIt() {
        #expect(toggle("hello Wor", up: true) == "hello WOR")
    }

    @Test func downLowercasesWord() {
        #expect(toggle("hello WoR", up: false) == "hello wor")
    }

    @Test func stopsAtWordBorderCharacters() {
        #expect(toggle("foo-bar", up: true) == "foo-Bar")
        #expect(toggle("(bar", up: true) == "(Bar")
    }

    @Test func noopAfterWhitespace() {
        let target = MockTextTarget()
        target.documentContextBeforeInput = "hallo "
        AdvancedTextFixtures.run(.toggleWordCapitalization(up: true), on: AdvancedTextFixtures.middleware(target: target))
        #expect(target.events.isEmpty)
    }

    @Test func usesLocaleForSharpS() {
        #expect(toggle("Straße", up: true) == "STRASSE")
    }
}

// MARK: - Clipboard

struct AdvancedTextMiddlewareClipboardTests {
    @Test func copyCopiesSelection() {
        let target = MockTextTarget()
        target.hasFullAccess = true
        target.selectedText = "picked"
        let clipboard = MockClipboard()
        AdvancedTextFixtures.run(.copy, on: AdvancedTextFixtures.middleware(target: target, clipboard: clipboard))
        #expect(clipboard.copied == ["picked"])
        #expect(target.events.isEmpty)
    }

    @Test func cutCopiesAndDeletesSelection() {
        let target = MockTextTarget()
        target.hasFullAccess = true
        target.selectedText = "picked"
        let clipboard = MockClipboard()
        AdvancedTextFixtures.run(.cut, on: AdvancedTextFixtures.middleware(target: target, clipboard: clipboard))
        #expect(clipboard.copied == ["picked"])
        #expect(target.events == [.deleteBackward])
    }

    @Test func copyWithoutSelectionCopiesWholeText() {
        let target = MockTextTarget()
        target.hasFullAccess = true
        target.documentContextBeforeInput = "hello "
        target.documentContextAfterInput = "world"
        let clipboard = MockClipboard()
        AdvancedTextFixtures.run(.copy, on: AdvancedTextFixtures.middleware(target: target, clipboard: clipboard))
        #expect(clipboard.copied == ["hello world"])
        #expect(target.events.isEmpty)
    }

    @Test func cutWithoutSelectionRemovesWholeText() {
        let target = MockTextTarget()
        target.hasFullAccess = true
        target.documentContextBeforeInput = "ab"
        target.documentContextAfterInput = "c"
        let clipboard = MockClipboard()
        AdvancedTextFixtures.run(.cut, on: AdvancedTextFixtures.middleware(target: target, clipboard: clipboard))
        #expect(clipboard.copied == ["abc"])
        #expect(target.events == [.adjustCursor(1), .deleteBackward, .deleteBackward, .deleteBackward])
    }

    @Test func cutWithoutSelectionUsesBridgeSelectAll() {
        let target = MockTextTarget()
        target.hasFullAccess = true
        target.documentContextBeforeInput = "ab"
        target.documentContextAfterInput = "c"
        let clipboard = MockClipboard()
        let bridge = SelectingBridge()
        bridge.target = target
        AdvancedTextFixtures.run(.cut, on: AdvancedTextFixtures.middleware(target: target, bridge: bridge, clipboard: clipboard))
        #expect(bridge.sent == [.selectAll])
        #expect(clipboard.copied == ["abc"])
        #expect(target.events == [.deleteBackward], "Deleting the selection removes it in one go")
    }

    @Test func clipboardNeedsFullAccess() {
        let target = MockTextTarget()
        target.hasFullAccess = false
        target.selectedText = "secret"
        let clipboard = MockClipboard()
        clipboard.pasteText = "x"
        let middleware = AdvancedTextFixtures.middleware(target: target, clipboard: clipboard)
        for action: KeyAction in [.copy, .cut, .paste] {
            AdvancedTextFixtures.run(action, on: middleware)
        }
        #expect(clipboard.copied.isEmpty)
        #expect(target.events.isEmpty)
    }

    @Test func pasteInsertsClipboardText() {
        let target = MockTextTarget()
        target.hasFullAccess = true
        let clipboard = MockClipboard()
        clipboard.pasteText = "pasted"
        AdvancedTextFixtures.run(.paste, on: AdvancedTextFixtures.middleware(target: target, clipboard: clipboard))
        #expect(target.events == [.insertText("pasted")])
    }
}

// MARK: - Bridged commands

struct AdvancedTextMiddlewareBridgeTests {
    @Test func historyAndSelectionCommandsGoThroughBridge() {
        let target = MockTextTarget()
        let bridge = MockTextCommandBridge()
        let middleware = AdvancedTextFixtures.middleware(target: target, bridge: bridge)
        for action: KeyAction in [.selectAll, .undo, .redo] {
            AdvancedTextFixtures.run(action, on: middleware)
        }
        #expect(bridge.sent == [.selectAll, .undo, .redo])
    }

    @Test func selectLineSelectsFromLineStartThroughNewline() {
        let target = MockTextTarget()
        target.documentContextBeforeInput = "a\nhello"
        target.documentContextAfterInput = " world\nnext"
        let bridge = MockTextCommandBridge()
        AdvancedTextFixtures.run(.selectLine, on: AdvancedTextFixtures.middleware(target: target, bridge: bridge))
        #expect(bridge.sent == [.selectRelative(start: -5, length: 12)])
    }

    @Test func unavailableBridgeDoesNothing() {
        let target = MockTextTarget()
        let bridge = MockTextCommandBridge()
        bridge.isAvailable = false
        let middleware = AdvancedTextFixtures.middleware(target: target, bridge: bridge)
        for action: KeyAction in [.selectAll, .selectLine, .undo, .redo] {
            AdvancedTextFixtures.run(action, on: middleware)
        }
        #expect(bridge.sent.isEmpty)
    }

    @Test func payloadPacksOpcodeSequenceAndArguments() {
        #expect(TextCommand.undo.payload(sequence: 7) == 0x0702)
        let extend = TextCommand.extendSelection(-3).payload(sequence: 1)
        #expect(extend & 0xFF == 5)
        #expect((extend >> 8) & 0xFF == 1)
        #expect((extend >> 16) & 0xFFFFFF == 0xFFFFFD)
        let select = TextCommand.selectRelative(start: -5, length: 12).payload(sequence: 0)
        #expect((select >> 40) & 0xFFFFFF == 12)
    }
}
