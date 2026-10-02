//
//  KeyboardHeightTests.swift
//  wurstfingerTests
//

import Foundation
import Testing
@testable import WurstfingerApp

struct KeyboardHeightTests {
    private typealias Calc = KeyboardConstants.Calculations

    @Test("Default aspect ratio makes square keys, like Thumb-Key")
    func defaultKeysAreSquare() {
        let gridWidth = Calc.gridWidth(viewWidth: 430, screenShortestSide: 430, scale: 1, split: false)
        let height = Calc.keyHeight(gridWidth: gridWidth, columns: 4, aspectRatio: DeviceLayoutUtils.defaultKeyAspectRatio)
        #expect(height == 107.5)
    }

    @Test("Wider aspect ratios make flatter keys")
    func aspectRatioIsWidthOverHeight() {
        #expect(Calc.keyHeight(gridWidth: 324, columns: 4, aspectRatio: 1.62) == 50)
    }

    @Test("Scale shrinks the grid and the keys with it")
    func scaleShrinksKeys() {
        let gridWidth = Calc.gridWidth(viewWidth: 430, screenShortestSide: 430, scale: 0.5, split: false)
        #expect(gridWidth == 215)
        #expect(Calc.keyHeight(gridWidth: gridWidth, columns: 4, aspectRatio: 1) == 53.75)
    }

    @Test("Landscape keeps the portrait grid width")
    func landscapeUsesShortSide() {
        #expect(Calc.gridWidth(viewWidth: 932, screenShortestSide: 430, scale: 1, split: false) == 430)
    }

    @Test("Each split copy is at most half the view")
    func splitHalvesTheGrid() {
        #expect(Calc.gridWidth(viewWidth: 430, screenShortestSide: 430, scale: 1, split: true) == 215)
        #expect(Calc.gridWidth(viewWidth: 430, screenShortestSide: 430, scale: 0.4, split: true) == 172)
    }

    @Test("Rendered height adds the fixed bar to the key rows")
    func renderedHeightAddsFixedParts() {
        let rows = KeyboardConstants.KeyDimensions.totalRows
        let fixed = KeyboardConstants.Layout.gridVerticalSpacing * CGFloat(rows - 1) +
            KeyboardConstants.Layout.verticalPaddingTop +
            KeyboardConstants.Layout.verticalPaddingBottom +
            KeyboardConstants.Layout.spellcheckBarHeight
        #expect(abs(Calc.renderedHeight(keyHeight: 50) - (50 * CGFloat(rows) + fixed)) < 0.0001)
        #expect(Calc.renderedHeight(keyHeight: 50, rows: 3) < Calc.renderedHeight(keyHeight: 50))
    }
}
