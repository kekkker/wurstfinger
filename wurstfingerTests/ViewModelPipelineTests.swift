//
//  ViewModelPipelineTests.swift
//  WurstfingerTests
//
//  End-to-end tests for the gesture → resolver → pipeline → text flow.
//  Each test constructs a real KeyboardViewModel with a real
//  KeyboardDefinition and a mock TextInputTarget, then exercises
//  handleGesture/handleSlide to verify observable side effects.
//

import Foundation
import Testing
@testable import WurstfingerApp

// Helpers (MockTextTarget, makeViewModel) are in TestHelpers.swift

// MARK: - Tap → commitText

@MainActor
@Suite(.serialized)
struct ViewModelTapTests {
    @Test func tapCenterKeyCommitsText() {
        let (vm, target) = makeViewModel()
        // German layout: top-left key center tap → "a"
        vm.handleGesture(.tap, keyId: GridSlot.topLeft, isReturn: false)
        #expect(target.events.contains(.insertText("a")))
    }

    @Test func tapCenterMiddleCommitsText() {
        let (vm, target) = makeViewModel()
        // German: center key center tap → "d"
        vm.handleGesture(.tap, keyId: GridSlot.center, isReturn: false)
        #expect(target.events.contains(.insertText("d")))
    }

    @Test func tapSpaceKeyCommitsSpace() {
        let (vm, target) = makeViewModel()
        vm.handleGesture(.tap, keyId: UtilitySlot.space, isReturn: false)
        #expect(target.events.contains(.insertText(" ")))
    }

    @Test func tapDeleteKeyDeletesBackward() {
        let (vm, target) = makeViewModel()
        target.documentContextBeforeInput = "x"
        vm.handleGesture(.tap, keyId: UtilitySlot.delete, isReturn: false)
        #expect(target.events.contains(.deleteBackward))
    }

    @Test func tapReturnKeyCommitsNewline() {
        let (vm, target) = makeViewModel()
        vm.handleGesture(.tap, keyId: UtilitySlot.return, isReturn: false)
        #expect(target.events.contains(.insertText("\n")))
    }
}

// MARK: - Swipe → correct character

@MainActor
@Suite(.serialized)
struct ViewModelSwipeTests {
    @Test func swipeDownRightFromTopLeftCommitsV() {
        let (vm, target) = makeViewModel()
        // German: top-left key, swipe down-right → "v"
        vm.handleGesture(.swipeDownRight, keyId: GridSlot.topLeft, isReturn: false)
        #expect(target.events.contains(.insertText("v")))
    }

    @Test func swipeUpFromCenterCommitsU() {
        let (vm, target) = makeViewModel()
        // German: center key, swipe up → "u"
        vm.handleGesture(.swipeUp, keyId: GridSlot.center, isReturn: false)
        #expect(target.events.contains(.insertText("u")))
    }

    @Test func swipeDownFromTopLeftCommitsAUmlaut() {
        let (vm, target) = makeViewModel()
        // German: top-left key, swipe down → "ä"
        vm.handleGesture(.swipeDown, keyId: GridSlot.topLeft, isReturn: false)
        #expect(target.events.contains(.insertText("ä")))
    }
}

// MARK: - Return swipe → returnAction

@MainActor
@Suite(.serialized)
struct ViewModelReturnSwipeTests {
    @Test func returnSwipeExecutesReturnAction() {
        // topLeft swipeRight: normal → "-", return → "÷"
        let (normalVM, normalTarget) = makeViewModel()
        normalVM.handleGesture(.swipeRight, keyId: GridSlot.topLeft, isReturn: false)

        let (returnVM, returnTarget) = makeViewModel()
        returnVM.handleGesture(.swipeRight, keyId: GridSlot.topLeft, isReturn: true)

        #expect(normalTarget.events.contains(.insertText("-")))
        #expect(returnTarget.events.contains(.insertText("÷")))
    }
}

// MARK: - Mode switching (shift)

@MainActor
@Suite(.serialized)
struct ViewModelModeTests {
    @Test func switchModeToShifted() {
        let (vm, _) = makeViewModel()
        #expect(vm.activeModeName == ModeNames.main)
        // Shift is swipeUp on midRight key
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.shifted)
    }

    @Test func shiftedModeAutoTransitionsBackAfterLetter() {
        let (vm, target) = makeViewModel()
        // Switch to shifted
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.shifted)
        // Type a letter — should auto-transition back to main
        vm.handleGesture(.tap, keyId: GridSlot.topLeft, isReturn: false)
        #expect(vm.activeModeName == ModeNames.main)
        // The committed text should be uppercase
        #expect(target.events.contains(.insertText("A")))
    }

    @Test func shiftWhileShiftedActivatesCapsLock() {
        let (vm, _) = makeViewModel()
        // First shift → shifted
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.shifted)
        // Second shift while shifted → capsLock (direct switchMode)
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.capsLock)
    }

    @Test func capsLockSwipeUpReleasesCapsLock() {
        let (vm, _) = makeViewModel()
        // Activate capsLock
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.capsLock)
        // Third swipe up toggles caps lock off, leaving a one-shot shift (Thumb-Key).
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.shifted)
    }

    @Test func capsLockSwipeDownGoesToMain() {
        let (vm, _) = makeViewModel()
        // Activate capsLock
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.capsLock)
        // Swipe down → back to main
        vm.handleGesture(.swipeDown, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.main)
    }

    @Test func capsLockStaysAfterLetter() {
        let (vm, target) = makeViewModel()
        // Activate capsLock
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.capsLock)
        // Type a letter — should stay in capsLock
        vm.handleGesture(.tap, keyId: GridSlot.topLeft, isReturn: false)
        #expect(vm.activeModeName == ModeNames.capsLock)
        #expect(target.events.contains(.insertText("A")))
    }

    @Test func switchToNumeric() {
        let (vm, _) = makeViewModel()
        // Tap symbols key → numeric mode
        vm.handleGesture(.tap, keyId: UtilitySlot.symbols, isReturn: false)
        #expect(vm.activeModeName == ModeNames.numeric)
    }

    @Test func shiftLegendChangesPerMode() throws {
        let (vm, _) = makeViewModel()

        // Main mode: ↑ shows the shift arrow.
        let mainMode = try #require(vm.activeModeFromDefinition)
        let mainMidRight = try #require(mainMode.keys[GridSlot.midRight])
        #expect(mainMidRight.bindings[.swipeUp]?.legend == .icon("arrowtriangle.up.fill"))

        // Shifted and caps lock: ↑ is the caps-lock toggle, whose icon changes while locked.
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.shifted)
        let shiftedMode = try #require(vm.activeModeFromDefinition)
        let shiftedMidRight = try #require(shiftedMode.keys[GridSlot.midRight])
        #expect(shiftedMidRight.bindings[.swipeUp]?.action == .toggleCapsLock)
        #expect(shiftedMidRight.bindings[.swipeUp]?.legend == .capsIcon("capslock", capsLockIcon: "c.circle"))

        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        #expect(vm.activeModeName == ModeNames.capsLock)
        let capsMode = try #require(vm.activeModeFromDefinition)
        let capsMidRight = try #require(capsMode.keys[GridSlot.midRight])
        #expect(capsMidRight.bindings[.swipeUp]?.action == .toggleCapsLock)
    }

    @Test func shiftDownHiddenInMainVisibleInShiftedAndCapsLock() throws {
        let (vm, _) = makeViewModel()

        // Main mode: ↓ unshifts but has no legend.
        let mainMode = try #require(vm.activeModeFromDefinition)
        let mainMidRight = try #require(mainMode.keys[GridSlot.midRight])
        #expect(mainMidRight.bindings[.swipeDown]?.action == .toggleShift(false))
        #expect(mainMidRight.bindings[.swipeDown]?.legend == .hidden)

        // Shifted mode: ↓ shows the unshift arrow.
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        let shiftedMode = try #require(vm.activeModeFromDefinition)
        let shiftedMidRight = try #require(shiftedMode.keys[GridSlot.midRight])
        #expect(shiftedMidRight.bindings[.swipeDown]?.legend == .icon("arrowtriangle.down.fill"))

        // CapsLock mode: same.
        vm.handleGesture(.swipeUp, keyId: GridSlot.midRight, isReturn: false)
        let capsMode = try #require(vm.activeModeFromDefinition)
        let capsMidRight = try #require(capsMode.keys[GridSlot.midRight])
        #expect(capsMidRight.bindings[.swipeDown]?.legend == .icon("arrowtriangle.down.fill"))
    }
}

// MARK: - Slide gestures

@MainActor
@Suite(.serialized)
struct ViewModelSlideTests {
    @Test func spaceTapCommitsSpace() {
        let (vm, target) = makeViewModel()
        vm.handleKeyEvent(.tap, keyId: UtilitySlot.space)
        #expect(target.events.contains(.insertText(" ")))
    }

    @Test func backspaceSlideWithoutBridgeDeletesProgressively() {
        let (vm, target) = makeViewModel()
        target.documentContextBeforeInput = "hello"
        vm.handleKeyEvent(.selectionBegan, keyId: UtilitySlot.delete)
        vm.handleKeyEvent(.selectionChanged(-2), keyId: UtilitySlot.delete)
        vm.handleKeyEvent(.deleteSelection, keyId: UtilitySlot.delete)
        #expect(target.events == [.deleteBackward, .deleteBackward])
    }

    @Test func backspaceSlideWithBridgeSelectsThenDeletes() {
        let (vm, target) = makeViewModel()
        let bridge = MockTextCommandBridge()
        vm.textCommandBridge = bridge
        vm.handleKeyEvent(.selectionBegan, keyId: UtilitySlot.delete)
        vm.handleKeyEvent(.selectionChanged(-3), keyId: UtilitySlot.delete)
        vm.handleKeyEvent(.deleteSelection, keyId: UtilitySlot.delete)
        #expect(bridge.sent == [.beginSelection, .extendSelection(-3)])
        #expect(target.events == [.deleteBackward])
    }

    @Test func spaceSlideMovesCursor() {
        let (vm, target) = makeViewModel()
        vm.handleKeyEvent(.slideCursor(2), keyId: UtilitySlot.space)
        #expect(target.events.contains(.adjustCursor(2)))
    }

    @Test func spaceSlideHoldMovesByCharacterThenWord() {
        let (vm, target) = makeViewModel()
        target.documentContextBeforeInput = "hello world"
        vm.handleKeyEvent(.slideHoldTick(.swipeLeft, word: false), keyId: UtilitySlot.space)
        vm.handleKeyEvent(.slideHoldTick(.swipeLeft, word: true), keyId: UtilitySlot.space)
        #expect(target.events == [.adjustCursor(-1), .adjustCursor(-5)])
    }
}

// MARK: - Definition loading

@MainActor
struct ViewModelDefinitionTests {
    @Test func loadDefinitionSetsActiveMode() {
        let (vm, _) = makeViewModel()
        #expect(vm.activeModeName == ModeNames.main)
        #expect(vm.currentDefinition != nil)
        #expect(vm.activeModeFromDefinition != nil)
    }

    @Test func loadDefinitionSetsArrangement() {
        let (vm, _) = makeViewModel()
        #expect(vm.currentArrangement != nil)
    }

    @Test func unknownLanguageIdDoesNotCrash() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let vm = KeyboardViewModel(userDefaults: defaults, shouldPersistSettings: false)
        vm.loadDefinition(for: "nonexistent_XX")
        #expect(vm.currentDefinition == nil)
        #expect(vm.activeModeFromDefinition == nil)
    }

    @Test func allLanguagesLoadSuccessfully() {
        for info in KeyboardRegistry.available {
            let definition = KeyboardRegistry.load(id: info.id)
            #expect(definition != nil, "Failed to load \(info.id)")
        }
    }
}

// MARK: - ViewControllerActionMiddleware integration

@MainActor
@Suite(.serialized)
struct ViewModelVCActionTests {
    @Test func advanceToNextInputModeCallsClosure() {
        var advanceCalled = false
        let (vm, _) = makeViewModel(
            advanceToNextInputMode: { advanceCalled = true }
        )
        // Input-method switch is bound to swipe-down on the emoji (globe) key.
        vm.handleGesture(.swipeDown, keyId: UtilitySlot.globe, isReturn: false)
        #expect(advanceCalled)
    }
}

// MARK: - Numpad style wiring

@MainActor
@Suite(.serialized)
struct ViewModelNumpadStyleTests {
    private func loadedNumericTopLeftDigit(numpadStyle: String?) -> String? {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        if let numpadStyle {
            defaults.set(numpadStyle, forKey: SettingsKey.numpadStyle.rawValue)
        }
        let vm = KeyboardViewModel(userDefaults: defaults, shouldPersistSettings: false)
        vm.loadDefinition(for: "de_DE")
        return vm.currentDefinition?
            .mode(ModeNames.numeric)?
            .keys[GridSlot.topLeft]?
            .bindings[.tap]?.label
    }

    @Test func defaultNumpadIsPhone() {
        // Phone layout: 1-2-3 in the top row.
        #expect(loadedNumericTopLeftDigit(numpadStyle: nil) == "1")
    }

    @Test func classicNumpadSwapsTopRow() {
        // Classic calculator layout: 7-8-9 in the top row.
        #expect(loadedNumericTopLeftDigit(numpadStyle: NumpadStyle.classic.rawValue) == "7")
    }
}
