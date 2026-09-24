//
//  KeyModificationsTests.swift
//  WurstfingerTests
//
//  The YAML reader and Thumb-Key's "Modify keys" format.
//

import Foundation
import Testing
@testable import WurstfingerApp

@MainActor
struct YAMLMappingTests {
    @Test func parsesNestedBlockMappings() throws {
        let node = try YAMLMapping.parse("""
        a:
          b: one # comment
          c:
            d: "two"
        """)
        #expect(node == .mapping([
            ("a", .mapping([
                ("b", .scalar("one")),
                ("c", .mapping([("d", .scalar("two"))])),
            ])),
        ]))
    }

    @Test func parsesFlowMappings() throws {
        let node = try YAMLMapping.parse("""
        key: { text: ê, size: SMALL }
        long: { longPress: { text: "1" } }
        """)
        #expect(node.entries?[0].value == .mapping([("text", .scalar("ê")), ("size", .scalar("SMALL"))]))
        #expect(node.entries?[1].value == .mapping([("longPress", .mapping([("text", .scalar("1"))]))]))
    }

    @Test func decodesEscapes() throws {
        let node = try YAMLMapping.parse(#"""
        a: "\u0301"
        b: "\U000121EB"
        c: 'it''s'
        d: "say \"hi\""
        e: "# not a comment"
        """#)
        let values = node.entries?.map(\.value.scalar)
        #expect(values == ["\u{0301}", "\u{121EB}", "it's", "say \"hi\"", "# not a comment"])
    }

    @Test func resolvesAnchorsAliasesAndMerges() throws {
        let node = try YAMLMapping.parse("""
        x-base: &base
          text: a
          size: SMALL
        one: *base
        two:
          <<: *base
          text: b
        """)
        #expect(node.entries?[1].value == .mapping([("text", .scalar("a")), ("size", .scalar("SMALL"))]))
        #expect(node.entries?[2].value == .mapping([("text", .scalar("b")), ("size", .scalar("SMALL"))]))
    }

    @Test func reportsLineOfErrors() {
        #expect(throws: YAMLError.self) { try YAMLMapping.parse("a:\n  b\n") }
        do {
            _ = try YAMLMapping.parse("a:\n\tb: c\n")
            Issue.record("Tabs must be rejected")
        } catch let error as YAMLError {
            #expect(error.line == 2)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func emptyDocumentIsEmptyMapping() throws {
        #expect(try YAMLMapping.parse("  \n# only a comment\n") == .mapping([]))
    }
}

@MainActor
struct KeyModificationsTests {
    private func definition(_ id: String = "en_US_thumbkey") throws -> KeyboardDefinition {
        try #require(KeyboardRegistry.load(id: id))
    }

    @Test func readmeExampleOneChangesCenterLetter() throws {
        let modified = try KeyModifications.apply("""
        ENThumbKey:
          main:
            key1_0:
              center:
                text: ñ
        """, to: definition())
        let key = modified.mode(ModeNames.main)?.key(for: GridSlot.midLeft)
        #expect(key?.bindings[.tap]?.action == .commitText("ñ"))
        #expect(key?.bindings[.tap]?.label == "ñ")
    }

    @Test func readmeExampleTwoAddsDirectionsAndRemovesSides() throws {
        let modified = try KeyModifications.apply("""
        ENThumbKey:
          main:
            key0_0:
              swipeType: EIGHT_WAY
              right: { text: ê }
              bottomRight: { remove: true }
          shifted:
            key0_0:
              swipeType: EIGHT_WAY
              right: { text: Ê }
        """, to: definition())
        let main = try #require(modified.mode(ModeNames.main)?.key(for: GridSlot.topLeft))
        #expect(main.swipeMode == .eightWay)
        #expect(main.bindings[.swipeRight]?.action == .commitText("ê"))
        #expect(main.bindings[.swipeDownRight] == nil)
        #expect(modified.mode(ModeNames.capsLock)?.key(for: GridSlot.topLeft)?.bindings[.swipeRight]?.label == "Ê")
    }

    @Test func readmeExampleThreeSwapsKeyActions() throws {
        let modified = try KeyModifications.apply("""
        ENThumbKey:
          main:
            key0_3:
              center:
                keyAction: SwitchLanguage
              left:
                keyAction: ToggleEmojiMode
        """, to: definition())
        let key = try #require(modified.mode(ModeNames.main)?.key(for: UtilitySlot.globe))
        #expect(key.bindings[.tap]?.action == .switchToNextLanguage)
        #expect(key.bindings[.swipeLeft]?.action == .openEmoji)
    }

    @Test func readmeExampleFourAddsLongPresses() throws {
        let modified = try KeyModifications.apply("""
        ENThumbKey:
          main:
            key0_0: { longPress: { text: "1" } }
            key3_0: { longPress: { text: "0" } }
        """, to: definition())
        #expect(modified.mode(ModeNames.main)?.key(for: GridSlot.topLeft)?.bindings[.longPress]?.action == .commitText("1"))
        #expect(modified.mode(ModeNames.main)?.key(for: UtilitySlot.space)?.bindings[.longPress]?.action == .commitText("0"))
    }

    @Test func displayTextAndSwipeReturn() throws {
        let modified = try KeyModifications.apply("""
        en_US_thumbkey:
          main:
            key0_1:
              bottom:
                text: "\\u0302"
                displayText: "◌̂"
                swipeReturnText: "¡"
              top: { keyAction: Copy, swipeReturnAction: Undo }
        """, to: definition())
        let key = try #require(modified.mode(ModeNames.main)?.key(for: GridSlot.topCenter))
        #expect(key.bindings[.swipeDown]?.action == .commitText("\u{0302}"))
        #expect(key.bindings[.swipeDown]?.label == "◌̂")
        #expect(key.bindings[.swipeDown]?.returnAction == .commitText("¡"))
        #expect(key.bindings[.swipeUp]?.action == .copy)
        #expect(key.bindings[.swipeUp]?.returnAction == .undo)
    }

    @Test func otherLayoutsAreUntouched() throws {
        let original = try definition("de_DE")
        let modified = try KeyModifications.apply("ENThumbKey:\n  main:\n    key1_0: { center: { text: ñ } }\n", to: original)
        #expect(modified == original)
    }

    @Test func invalidConfigsExplainTheProblem() {
        let broken = [
            "ENThumbKey:\n  main:\n    key0_0: { center: { text: a, keyAction: Copy } }\n",
            "ENThumbKey:\n  main:\n    key9_9: { center: { text: a } }\n",
            "ENThumbKey:\n  main:\n    key0_0: { swipeType: SIX_WAY }\n",
            "ENThumbKey:\n  main:\n    key0_0: { center: { keyAction: Teleport } }\n",
            "ENThumbKey:\n  sideways:\n    key0_0: { center: { text: a } }\n",
            "NoSuchLayout:\n  main:\n    key0_0: { center: { text: a } }\n",
        ]
        for yaml in broken {
            #expect(throws: KeyModificationError.self, "\(yaml)") { try KeyModifications.validate(yaml) }
        }
    }

    @Test func widthMustFitTheRow() {
        #expect(throws: KeyModificationError.self) {
            try KeyModifications.validate("ENThumbKey:\n  main:\n    key3_0: { widthMultiplier: 2 }\n")
        }
    }

    @Test func viewModelAppliesStoredModifications() {
        let (vm, target) = makeViewModel(
            languageId: "en_US_thumbkey",
            settings: [.keyModifications: "ENThumbKey:\n  main:\n    key1_0: { center: { text: ñ } }\n"]
        )
        vm.handleKeyEvent(.tap, keyId: GridSlot.midLeft)
        #expect(target.insertedTexts == ["ñ"])
    }

    @Test func brokenStoredModificationsKeepTheLayout() {
        let (vm, target) = makeViewModel(
            languageId: "en_US_thumbkey",
            settings: [.keyModifications: "ENThumbKey:\n  main:\n    key1_0: { center: { text: ñ, keyAction: Copy } }\n"]
        )
        vm.handleKeyEvent(.tap, keyId: GridSlot.midLeft)
        #expect(target.insertedTexts == ["n"])
    }
}
