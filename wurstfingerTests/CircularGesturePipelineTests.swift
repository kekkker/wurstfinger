//
//  CircularGesturePipelineTests.swift
//  WurstfingerTests
//
//  Tests for KeyboardViewModel's circular-gesture handling (explicit circle
//  bindings, opposite-case and number-key circles), driven end-to-end through the
//  data-driven pipeline via makeViewModel + MockTextTarget.
//

import Foundation
import Testing
@testable import WurstfingerApp

@MainActor
struct CircularGesturePipelineTests {
    /// Path 2: a plain letter key with no explicit circular binding inserts
    /// the uppercase center character.
    @Test func clockwiseOnLetterKeyInsertsUppercase() {
        let (vm, target) = makeViewModel(languageId: "de_DE")

        guard let key = vm.activeModeFromDefinition?.key(for: GridSlot.topLeft),
              case let .commitText(letter) = key.bindings[.tap]?.action,
              key.bindings[.circularClockwise] == nil
        else {
            Issue.record("Expected topLeft to be a plain letter key without an explicit circular binding")
            return
        }

        vm.handleGesture(.circularClockwise, keyId: GridSlot.topLeft, isReturn: false)

        // Match production: tryCircularUppercase uppercases with the pipeline
        // locale, so locale-sensitive letters can't drift from the assertion.
        #expect(target.events.contains(.insertText(letter.uppercased(with: vm.pipelineLocale ?? .current))))
    }

    /// Counterclockwise types the number-layer key at the same position
    /// (Thumb-Key's default circle action).
    @Test func counterclockwiseOnLetterKeyInsertsNumber() {
        let (vm, target) = makeViewModel(languageId: "de_DE")

        vm.handleGesture(.circularCounterclockwise, keyId: GridSlot.topLeft, isReturn: false)

        #expect(target.events == [.insertText("1")])
    }

    /// The circle actions follow the settings.
    @Test func circleActionsFollowSettings() {
        let (vm, target) = makeViewModel(
            languageId: "de_DE",
            settings: [
                .clockwiseDragAction: CircularDragAction.numeric.rawValue,
                .counterclockwiseDragAction: CircularDragAction.oppositeCase.rawValue,
            ]
        )

        vm.handleGesture(.circularClockwise, keyId: GridSlot.topLeft, isReturn: false)
        vm.handleGesture(.circularCounterclockwise, keyId: GridSlot.topLeft, isReturn: false)

        #expect(target.events == [.insertText("1"), .insertText("A")])
    }

    /// Path 1: numeric layer keys carry an explicit circular binding
    /// (superscripts / math symbols) which takes precedence over uppercasing.
    @Test func circularInNumericModeDispatchesExplicitBinding() {
        let (vm, target) = makeViewModel(languageId: "de_DE")

        vm.handleGesture(.tap, keyId: UtilitySlot.symbols, isReturn: false)
        #expect(vm.activeModeName == ModeNames.numeric)

        guard let key = vm.activeModeFromDefinition?.key(for: GridSlot.topLeft),
              case let .commitText(symbol) = key.bindings[.circularClockwise]?.action
        else {
            Issue.record("Expected numeric topLeft to carry an explicit circular binding")
            return
        }

        vm.handleGesture(.circularClockwise, keyId: GridSlot.topLeft, isReturn: false)

        #expect(target.events.contains(.insertText(symbol)))
    }

    /// An unknown key id is ignored (guard in handleCircular).
    @Test func circularOnUnknownKeyIsNoop() {
        let (vm, target) = makeViewModel(languageId: "de_DE")

        vm.handleGesture(.circularClockwise, keyId: "nonexistent-key", isReturn: false)

        #expect(target.events.isEmpty)
    }
}
