//
//  CommonKeysFactoryTests.swift
//  WurstfingerTests
//
//  Tests for CommonKeys, StandardArrangements, and GridKeyboardFactory.
//

import Foundation
import Testing
@testable import WurstfingerApp

// MARK: - CommonKeys Tests

struct CommonKeysTests {
    @Test func allUtilityKeysContainsExpectedKeys() {
        let keys = CommonKeys.allUtilityKeys
        #expect(keys.count == 5)
        #expect(keys[UtilitySlot.globe] != nil)
        #expect(keys[UtilitySlot.delete] != nil)
        #expect(keys[UtilitySlot.return] != nil)
        #expect(keys[UtilitySlot.symbols] != nil)
        #expect(keys[UtilitySlot.space] != nil)
    }

    @Test func globeSlotIsThumbKeysEmojiKey() {
        let globe = CommonKeys.globe
        #expect(globe.id == UtilitySlot.globe)
        #expect(globe.bindings[.tap]?.action == .openEmoji)
        #expect(globe.bindings[.swipeUp]?.action == .openSettings)
        #expect(globe.bindings[.swipeUpLeft]?.action == .toggleHideLetters)
        #expect(globe.bindings[.swipeLeft]?.action == .switchToNextLanguage)
        #expect(globe.bindings[.swipeRight]?.action == .cycleKeyboardPosition)
        #expect(globe.bindings[.swipeDown]?.action == .advanceToNextInputMode)
        #expect(globe.bindings[.swipeDownLeft]?.action == .dismissKeyboard)
        #expect(globe.style == .utility)
    }

    @Test func deleteKeyDeletesWords() {
        let delete = CommonKeys.delete
        #expect(delete.slideType == .delete)
        #expect(delete.swipeMode == .twoWayHorizontal)
        #expect(delete.bindings[.swipeLeft]?.action == .deleteWordBackward)
        #expect(delete.bindings[.swipeRight]?.action == .deleteWordForward)
        #expect(delete.bindings[.longPress]?.action == .deleteWordBackward)
        #expect(delete.bindings[.swipeLeft]?.legend == .hidden)
    }

    @Test func spacebarMovesCursorAndCyclesPunctuation() {
        let space = CommonKeys.spacebar
        #expect(space.slideType == .moveCursor)
        #expect(space.swipeMode == .eightWay)
        #expect(space.bindings[.tap]?.action == .space)
        #expect(space.bindings[.swipeLeft]?.action == .moveCursor(offset: -1))
        #expect(space.bindings[.swipeRight]?.action == .moveCursor(offset: 1))
        #expect(space.bindings[.swipeDownLeft]?.action == .moveWordBackward)
        #expect(space.bindings[.swipeDownRight]?.action == .moveWordForward)
        #expect(space.bindings[.swipeUp]?.action == .cursorToLineStart)
        #expect(space.bindings[.swipeUp]?.returnAction == .cursorToTextStart)
        #expect(space.bindings[.swipeDown]?.returnAction == .cursorToTextEnd)
        #expect(space.tapCycleActions?.first == .replaceLastText(", ", trimCount: 1))
        #expect(space.tapCycleActions?.count == 6)
    }

    @Test func symbolsKeySwitchesToNumericWithTextEditSwipes() {
        let symbols = CommonKeys.symbols
        #expect(symbols.bindings[.tap]?.action == .switchMode(ModeNames.numeric))
        #expect(symbols.bindings[.swipeUp]?.action == .copy)
        #expect(symbols.bindings[.swipeUpLeft]?.action == .selectAll)
        #expect(symbols.bindings[.swipeUpLeft]?.returnAction == .selectLine)
        #expect(symbols.bindings[.swipeUpRight]?.action == .cut)
        #expect(symbols.bindings[.swipeDownLeft]?.action == .undo)
        #expect(symbols.bindings[.swipeDownRight]?.action == .redo)
        #expect(symbols.bindings[.swipeDown]?.action == .paste)
        #expect(symbols.bindings[.swipeDown]?.returnAction == .openClipboardHistory)
    }

    @Test func returnLongPressIsNewline() {
        #expect(CommonKeys.return.bindings[.tap]?.action == .newline)
        #expect(CommonKeys.return.bindings[.longPress]?.action == .newline)
    }

    @Test func defaultSlotBindingsCoversAllNonCenterSlots() {
        let bindings = CommonKeys.defaultSlotBindings
        // All slots except center should have defaults
        #expect(bindings[GridSlot.topLeft] != nil)
        #expect(bindings[GridSlot.topCenter] != nil)
        #expect(bindings[GridSlot.topRight] != nil)
        #expect(bindings[GridSlot.midLeft] != nil)
        #expect(bindings[GridSlot.center] == nil) // center has no defaults
        #expect(bindings[GridSlot.midRight] != nil)
        #expect(bindings[GridSlot.bottomLeft] != nil)
        #expect(bindings[GridSlot.bottomCenter] != nil)
        #expect(bindings[GridSlot.bottomRight] != nil)
    }

    @Test func midRightSwipeUpIsShift() throws {
        let midRight = try #require(CommonKeys.defaultSlotBindings[GridSlot.midRight])
        let shiftBinding = try #require(midRight[.swipeUp])
        #expect(shiftBinding.action == .toggleShift(true))
        #expect(shiftBinding.returnAction == .toggleWordCapitalization(up: true))
        #expect(shiftBinding.resolvedCategory == .modifier)
        #expect(midRight[.swipeDown]?.action == .toggleShift(false))
        #expect(midRight[.swipeDown]?.returnAction == .toggleWordCapitalization(up: false))
    }

    @Test func topCenterComposeBindings() throws {
        let topCenter = try #require(CommonKeys.defaultSlotBindings[GridSlot.topCenter])
        #expect(topCenter[.swipeUp]?.action == .compose(trigger: "^"))
        #expect(topCenter[.swipeUpLeft]?.action == .compose(trigger: "ˋ"))
        #expect(topCenter[.swipeUpRight]?.action == .compose(trigger: "´"))
    }

    @Test func bottomLeftComposeBinding() throws {
        let bottomLeft = try #require(CommonKeys.defaultSlotBindings[GridSlot.bottomLeft])
        #expect(bottomLeft[.swipeUp]?.action == .compose(trigger: "¨"))
    }

    @Test func returnActionsPresent() throws {
        // Spot-check return actions
        let topLeft = try #require(CommonKeys.defaultSlotBindings[GridSlot.topLeft])
        #expect(topLeft[.swipeRight]?.returnAction == .commitText("÷"))

        let topRight = try #require(CommonKeys.defaultSlotBindings[GridSlot.topRight])
        #expect(topRight[.swipeLeft]?.returnAction == .commitText("¿"))
    }
}

// MARK: - StandardArrangements Tests

struct StandardArrangementsTests {
    @Test func grid3x3HasAllFourContexts() {
        let arrangements = StandardArrangements.grid3x3
        #expect(arrangements.count == 4)
        #expect(arrangements[.portrait] != nil)
        #expect(arrangements[.portraitUtilityLeft] != nil)
        #expect(arrangements[.landscape] != nil)
        #expect(arrangements[.landscapeUtilityLeft] != nil)
    }

    @Test func portraitHasFourColumns() throws {
        let portrait = try #require(StandardArrangements.grid3x3[.portrait])
        #expect(portrait.columns == 4)
        #expect(portrait.rows.count == 4)
    }

    @Test func landscapeHasFiveColumns() throws {
        let landscape = try #require(StandardArrangements.grid3x3[.landscape])
        #expect(landscape.columns == 5)
        #expect(landscape.rows.count == 3)
    }

    @Test func portraitUtilityLeftIsMirroredPortrait() throws {
        let portrait = try #require(StandardArrangements.grid3x3[.portrait])
        let utilityLeft = try #require(StandardArrangements.grid3x3[.portraitUtilityLeft])
        #expect(utilityLeft == portrait.mirroredHorizontally())
    }

    @Test func landscapeUtilityLeftIsMirroredLandscape() throws {
        let landscape = try #require(StandardArrangements.grid3x3[.landscape])
        let utilityLeft = try #require(StandardArrangements.grid3x3[.landscapeUtilityLeft])
        #expect(utilityLeft == landscape.mirroredHorizontally())
    }

    @Test func portraitFirstRowContainsGridAndGlobe() throws {
        let portrait = try #require(StandardArrangements.grid3x3[.portrait])
        let firstRowIds = portrait.rows[0].map(\.keyId)
        #expect(firstRowIds == [GridSlot.topLeft, GridSlot.topCenter, GridSlot.topRight, UtilitySlot.globe])
    }

    @Test func portraitSpaceBarSpansThreeColumns() throws {
        let portrait = try #require(StandardArrangements.grid3x3[.portrait])
        let space = try #require(portrait.rows[3].first { $0.keyId == UtilitySlot.space })
        #expect(space.widthMultiplier == 3)
    }

    @Test func landscapeReturnSpansTwoRows() throws {
        let landscape = try #require(StandardArrangements.grid3x3[.landscape])
        let returnKey = try #require(landscape.rows[1].first { $0.keyId == UtilitySlot.return })
        #expect(returnKey.heightMultiplier == 2)
    }
}

// MARK: - GridKeyboardFactory Tests

struct GridKeyboardFactoryTests {
    /// Minimal test layout for factory testing.
    static let testLayout = GridKeyboardFactory.layout(
        id: "test_messagease",
        title: "Test MessagEase",
        localeIdentifier: "en_US",
        centerCharacters: [
            ["a", "b", "c"],
            ["d", "e", "f"],
            ["g", "h", "i"],
        ]
    )

    @Test func factoryProducesAllModes() {
        let layout = Self.testLayout
        #expect(layout.modes[ModeNames.main] != nil)
        #expect(layout.modes[ModeNames.shifted] != nil)
        #expect(layout.modes[ModeNames.capsLock] != nil)
        #expect(layout.modes[ModeNames.numeric] != nil)
    }

    @Test func factoryResultValidatesWithoutErrors() {
        let errors = Self.testLayout.validate()
        #expect(errors.isEmpty, "Validation errors: \(errors)")
    }

    @Test func mainModeHasAllKeys() throws {
        let main = try #require(Self.testLayout.modes[ModeNames.main])
        // 9 grid slots + 5 utility keys = 14
        #expect(main.keys.count == 14)
        #expect(main.keys[GridSlot.topLeft] != nil)
        #expect(main.keys[GridSlot.center] != nil)
        #expect(main.keys[UtilitySlot.globe] != nil)
        #expect(main.keys[UtilitySlot.space] != nil)
    }

    @Test func centerCharactersBecomeTapActions() throws {
        let main = try #require(Self.testLayout.modes[ModeNames.main])
        #expect(main.keys[GridSlot.topLeft]?.bindings[.tap]?.action == .commitText("a"))
        #expect(main.keys[GridSlot.center]?.bindings[.tap]?.action == .commitText("e"))
        #expect(main.keys[GridSlot.bottomRight]?.bindings[.tap]?.action == .commitText("i"))
    }

    @Test func defaultBindingsMergedIntoLetterKeys() throws {
        let main = try #require(Self.testLayout.modes[ModeNames.main])
        // topLeft should have the default "-" on swipeRight
        let topLeft = try #require(main.keys[GridSlot.topLeft])
        #expect(topLeft.bindings[.swipeRight]?.action == .commitText("-"))
    }

    @Test func shiftedModeHasNoAutoTransitions() throws {
        // One-shot shift comes from the auto-capitalization middleware, which
        // unshifts after any committed text (Thumb-Key).
        let shifted = try #require(Self.testLayout.modes[ModeNames.shifted])
        #expect(shifted.autoTransitions.isEmpty)
    }

    @Test func shiftedSwipeUpTogglesCapsLock() throws {
        let shifted = try #require(Self.testLayout.modes[ModeNames.shifted])
        let midRight = try #require(shifted.keys[GridSlot.midRight])
        let swipeUp = try #require(midRight.bindings[.swipeUp])
        #expect(swipeUp.action == .toggleCapsLock)
        #expect(swipeUp.legend == .capsIcon("capslock", capsLockIcon: "c.circle"))
    }

    @Test func capsLockSharesShiftedKeys() throws {
        let capsLock = try #require(Self.testLayout.modes[ModeNames.capsLock])
        let shifted = try #require(Self.testLayout.modes[ModeNames.shifted])
        #expect(capsLock.keys == shifted.keys)
        #expect(capsLock.autoTransitions.isEmpty)
        #expect(capsLock.doubleTapMode == nil)
    }

    @Test func mainModeShiftLegendIsUpArrow() throws {
        let main = try #require(Self.testLayout.modes[ModeNames.main])
        let midRight = try #require(main.keys[GridSlot.midRight])
        let swipeUp = try #require(midRight.bindings[.swipeUp])
        #expect(swipeUp.action == .toggleShift(true))
        #expect(swipeUp.legend == .icon("arrowtriangle.up.fill"))
    }

    @Test func thumbKeyLayoutsUseThumbKeyNumberLayer() throws {
        let definition = try #require(KeyboardRegistry.load(id: "en_US_thumbkey"))
        #expect(definition.settings.numericLayout == .thumbKey)
        let numeric = try #require(definition.modes[ModeNames.numeric])
        #expect(numeric.keys[GridSlot.bottomCenter]?.bindings[.swipeLeft]?.action == .commitText(","))
        let zero = try #require(numeric.arrangement(for: .portrait)?.rows.last?.first)
        #expect(zero.keyId == GridSlot.zero)
        #expect(zero.widthMultiplier == 2)
    }

    @Test func thumbKeyLayoutsUseThumbKeyDirectionZones() throws {
        let main = try #require(KeyboardRegistry.load(id: "en_US_thumbkey")?.modes[ModeNames.main])
        #expect(main.keys[GridSlot.topLeft]?.swipeMode == .fourWayDiagonal)
        #expect(main.keys[GridSlot.topCenter]?.swipeMode == .twoWayVertical)
        #expect(main.keys[GridSlot.midLeft]?.swipeMode == .twoWayHorizontal)
        #expect(main.keys[GridSlot.center]?.swipeMode == .eightWay)
        #expect(main.keys[GridSlot.midRight]?.swipeMode == .fourWayCross)
        #expect(main.keys[GridSlot.bottomCenter]?.bindings[.swipeDown]?.legend == .muted)
    }

    @Test func shiftedLettersAreUppercased() throws {
        let shifted = try #require(Self.testLayout.modes[ModeNames.shifted])
        #expect(shifted.keys[GridSlot.topLeft]?.bindings[.tap]?.action == .commitText("A"))
        #expect(shifted.keys[GridSlot.center]?.bindings[.tap]?.action == .commitText("E"))
    }

    @Test func directionalOverridesReplaceDefaults() throws {
        let layout = GridKeyboardFactory.layout(
            id: "test_override",
            title: "Test Override",
            localeIdentifier: "en_US",
            centerCharacters: [
                ["a", "b", "c"],
                ["d", "e", "f"],
                ["g", "h", "i"],
            ],
            directionalOverrides: [
                GridSlot.topLeft: [.swipeRight: "x"],
            ]
        )
        let main = try #require(layout.modes[ModeNames.main])
        // The default "-" on topLeft.swipeRight should be replaced by "x"
        #expect(main.keys[GridSlot.topLeft]?.bindings[.swipeRight]?.action == .commitText("x"))
        #expect(main.keys[GridSlot.topLeft]?.bindings[.swipeRight]?.label == "x")
    }

    @Test func defaultModeIsMain() {
        #expect(Self.testLayout.defaultMode == ModeNames.main)
    }

    @Test func localeIsPreserved() {
        #expect(Self.testLayout.localeIdentifier == "en_US")
    }
}
