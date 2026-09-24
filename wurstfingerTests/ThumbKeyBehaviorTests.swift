//
//  ThumbKeyBehaviorTests.swift
//  WurstfingerTests
//
//  End-to-end view-model tests for the Thumb-Key behaviors: multi-tap space,
//  swipe-and-return case flips, one-shot shift, auto-capitalization, the
//  starting layer per field, direction zones and the utility actions.
//

import Foundation
import Testing
@testable import WurstfingerApp

private func outcome(_ direction: GestureType?, isReturn: Bool = false) -> KeyGestureEvent {
    .drag(DragOutcome(finalDirection: direction, maxDirection: direction, isReturn: isReturn, circular: nil))
}

@MainActor
@Suite(.serialized)
struct SpacebarMultiTapTests {
    @Test func repeatedTapsCyclePunctuation() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        target.documentContextBeforeInput = "hi"
        for _ in 0 ..< 3 {
            vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        }
        #expect(target.documentContextBeforeInput == "hi. ")
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        #expect(target.documentContextBeforeInput == "hi? ")
    }

    @Test func cycleWrapsToANewSpace() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        target.documentContextBeforeInput = "a"
        for _ in 0 ..< 8 {
            vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        }
        // " " , ", " ". " "? " "! " ": " "; " then a fresh space.
        #expect(target.documentContextBeforeInput == "a;  ")
    }

    @Test func otherKeyInBetweenRestartsTheCycle() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        #expect(target.documentContextBeforeInput == " s ")
    }

    @Test func movedCursorRestartsTheCycle() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        target.documentContextBeforeInput = "elsewhere"
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        #expect(target.documentContextBeforeInput == "elsewhere ")
    }

    @Test func multiTapCanBeTurnedOff() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey", settings: [.spacebarMultiTaps: false])
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        #expect(target.documentContextBeforeInput == "  ")
    }
}

@MainActor
@Suite(.serialized)
struct SwipeResolutionTests {
    @Test func returnSwipeTypesOppositeCase() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        // "a" key (midRight) ← is "l"; returning gives "L".
        vm.handleKeyEvent(outcome(.swipeLeft, isReturn: true), keyId: GridSlot.midRight)
        #expect(target.insertedTexts == ["L"])
    }

    @Test func returnSwipeOnShiftedLayerTypesLowercase() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleKeyEvent(outcome(.swipeLeft, isReturn: true), keyId: GridSlot.midRight)
        #expect(target.insertedTexts == ["l"])
    }

    @Test func unassignedDirectionTypesTheTapLetter() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        // "r" (topCenter) only has ↓ "g"; ↑ types "r".
        vm.handleKeyEvent(outcome(.swipeUp), keyId: GridSlot.topCenter)
        #expect(target.insertedTexts == ["r"])
    }

    @Test func shortDragTypesTheTapLetter() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleKeyEvent(outcome(nil), keyId: GridSlot.center)
        #expect(target.insertedTexts == ["h"])
    }

    @Test func ghostKeysReachNumberLayerSymbols() {
        let (plain, plainTarget) = makeViewModel(languageId: "en_US_thumbkey")
        plain.handleKeyEvent(outcome(.swipeLeft), keyId: GridSlot.bottomCenter)
        #expect(plainTarget.insertedTexts == ["i"], "Without ghost keys the tap letter is typed")

        let (ghost, ghostTarget) = makeViewModel(languageId: "en_US_thumbkey", settings: [.ghostKeysEnabled: true])
        ghost.handleKeyEvent(outcome(.swipeLeft), keyId: GridSlot.bottomCenter)
        #expect(ghostTarget.insertedTexts == [","], "The number layer's 8 has , on ←")
    }

    @Test func thumbKeyZonesWidenDirections() {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey")
        let key = vm.activeModeFromDefinition?.key(for: GridSlot.topLeft)
        let config = key.map { vm.gestureConfig(for: $0, keySize: 60, pixelScale: 3) }
        #expect(config?.directionMode == .fourWayDiagonal)
        #expect(config?.minSwipeLength == 40)
        #expect(config?.touchSlop == 24)
        #expect(config?.keySize == 180)
    }
}

@MainActor
@Suite(.serialized)
struct ShiftAndCapitalizationTests {
    @Test func shiftAppliesToOneCharacter() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        #expect(target.insertedTexts == ["S", "s"])
    }

    @Test func shiftEndsAfterPunctuationToo() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleKeyEvent(outcome(.swipeDown), keyId: GridSlot.bottomCenter)
        #expect(target.insertedTexts == ["."])
        #expect(vm.activeModeName == ModeNames.main)
    }

    @Test func capsLockSurvivesTyping() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        #expect(target.insertedTexts == ["S", " ", "S"])
        #expect(vm.activeModeName == ModeNames.capsLock)
    }

    @Test func autoCapitalizesSentenceStarts() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey", autoCapitalize: true)
        target.documentContextBeforeInput = "done"
        vm.handleKeyEvent(outcome(.swipeDown), keyId: GridSlot.bottomCenter) // "."
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        #expect(target.documentContextBeforeInput == "done. S")
    }

    @Test func autoCapitalizationRespectsFieldSetting() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey", autoCapitalize: true)
        target.capitalizationMode = .none
        target.documentContextBeforeInput = "done. "
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        #expect(target.documentContextBeforeInput?.hasSuffix("s") == true)
    }

    @Test func englishCapitalizesLoneI() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey", autoCapitalize: true)
        target.documentContextBeforeInput = "so i"
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        #expect(target.documentContextBeforeInput == "so I ")
    }

    @Test func wordCapitalizationReturnSwipes() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        target.documentContextBeforeInput = "hello"
        vm.handleKeyEvent(outcome(.swipeUp, isReturn: true), keyId: GridSlot.midRight)
        #expect(target.documentContextBeforeInput == "Hello")
        vm.handleKeyEvent(outcome(.swipeUp, isReturn: true), keyId: GridSlot.midRight)
        #expect(target.documentContextBeforeInput == "HELLO")
        vm.handleKeyEvent(outcome(.swipeDown, isReturn: true), keyId: GridSlot.midRight)
        #expect(target.documentContextBeforeInput == "hello")
    }
}

@MainActor
@Suite(.serialized)
struct StartingLayerTests {
    @Test func numberFieldsStartOnNumbers() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        target.fieldKind = .number
        vm.resetModeForCurrentField()
        #expect(vm.activeModeName == ModeNames.numeric)
    }

    @Test func emptySentenceFieldStartsShifted() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey", autoCapitalize: true)
        // The view model holds the target weakly.
        withExtendedLifetime(target) {
            vm.resetModeForCurrentField()
        }
        #expect(vm.activeModeName == ModeNames.shifted)
    }

    @Test func addressFieldsStartLowercase() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey", autoCapitalize: true)
        target.fieldKind = .addressOrPassword
        vm.resetModeForCurrentField()
        #expect(vm.activeModeName == ModeNames.main)
    }

    @Test func newFieldClosesPanels() {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.globe)
        #expect(vm.emojiActive)
        vm.resetModeForCurrentField()
        #expect(!vm.emojiActive)
    }

    @Test func switchToLettersAfterSpace() {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey", settings: [.switchToLettersAfterSpace: true])
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.symbols)
        #expect(vm.activeModeName == ModeNames.numeric)
        vm.handleKeyEvent(.tap, keyId: GridSlot.topLeft)
        #expect(vm.activeModeName == ModeNames.numeric)
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        #expect(vm.activeModeName == ModeNames.main)
    }
}

@MainActor
@Suite(.serialized)
struct UtilityActionTests {
    @Test func emojiKeyOpensAndClosesPanels() {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.globe)
        #expect(vm.emojiActive)
        vm.closeEmoji()
        #expect(!vm.emojiActive)
    }

    @Test func pasteReturnSwipeOpensClipboardHistory() {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleKeyEvent(outcome(.swipeDown, isReturn: true), keyId: UtilitySlot.symbols)
        #expect(vm.clipboardActive)
    }

    @Test func switchingLayersClosesPanels() throws {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey")
        vm.openEmoji()
        try vm.perform(#require(CommonKeys.symbols.bindings[.tap]))
        #expect(!vm.emojiActive)
        #expect(vm.activeModeName == ModeNames.numeric)
    }

    @Test func hideLettersToggles() {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey")
        vm.handleKeyEvent(outcome(.swipeUpLeft), keyId: UtilitySlot.globe)
        #expect(vm.sharedDefaults.bool(forKey: SettingsKey.hideLetters.rawValue))
        vm.handleKeyEvent(outcome(.swipeUpLeft), keyId: UtilitySlot.globe)
        #expect(!vm.sharedDefaults.bool(forKey: SettingsKey.hideLetters.rawValue))
    }

    @Test func moveKeyboardCyclesLikeThumbKey() {
        let (vm, _) = makeViewModel(languageId: "en_US_thumbkey")
        let split = { vm.sharedDefaults.bool(forKey: SettingsKey.keyboardSplit.rawValue) }
        vm.keyboardHorizontalPosition = 0.5
        vm.cycleKeyboardPosition()
        #expect(vm.keyboardHorizontalPosition == 1 && !split())
        vm.cycleKeyboardPosition()
        #expect(vm.keyboardHorizontalPosition == 0 && !split())
        vm.cycleKeyboardPosition()
        #expect(split())
        vm.cycleKeyboardPosition()
        #expect(vm.keyboardHorizontalPosition == 0.5 && !split())
    }

    @Test func backspaceSwipesDeleteWords() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        target.documentContextBeforeInput = "one two"
        vm.handleKeyEvent(outcome(.swipeLeft), keyId: UtilitySlot.delete)
        #expect(target.documentContextBeforeInput == "one ")
        vm.handleKeyEvent(.longPress, keyId: UtilitySlot.delete)
        #expect(target.documentContextBeforeInput == "")
    }

    @Test func undoGoesThroughBridge() {
        let (vm, target) = makeViewModel(languageId: "en_US_thumbkey")
        let bridge = MockTextCommandBridge()
        vm.textCommandBridge = bridge
        // The view model holds the target weakly.
        withExtendedLifetime(target) {
            vm.handleKeyEvent(outcome(.swipeDownLeft), keyId: UtilitySlot.symbols)
            vm.handleKeyEvent(outcome(.swipeDownRight), keyId: UtilitySlot.symbols)
        }
        #expect(bridge.sent == [.undo, .redo])
    }
}
