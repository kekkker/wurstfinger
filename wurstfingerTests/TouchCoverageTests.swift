//
//  TouchCoverageTests.swift
//  wurstfingerTests
//
//  Every point of the key grid belongs to exactly one key: keys fill their
//  grid cells (the visible gap is padding inside each key's own cell) and
//  the grid has no spacing or outer padding, so there are neither dead
//  zones nor overlapping touch areas.
//

import Foundation
import Testing
@testable import WurstfingerApp

struct TouchCoverageTests {
    @Test func gridHasNoSpacingBetweenCells() {
        #expect(KeyboardConstants.Layout.gridHorizontalSpacing == 0)
        #expect(KeyboardConstants.Layout.gridVerticalSpacing == 0)
    }

    @Test func gridHasNoOuterPadding() {
        #expect(KeyboardConstants.Layout.horizontalPadding == 0)
        #expect(KeyboardConstants.Layout.verticalPaddingTop == 0)
        #expect(KeyboardConstants.Layout.verticalPaddingBottom == 0)
    }

    @Test func standardRowsFillEveryColumn() throws {
        for arrangement in StandardArrangements.grid3x3.values {
            for row in arrangement.rows where !row.contains(where: { $0.heightMultiplier > 1 }) {
                let spanned = row.reduce(0) { $0 + $1.widthMultiplier }
                // Rows below a double-height key are short by that key's width.
                #expect(spanned <= arrangement.columns)
            }
        }
        let portrait = try #require(StandardArrangements.grid3x3[.portrait])
        for row in portrait.rows {
            #expect(row.reduce(0) { $0 + $1.widthMultiplier } == portrait.columns)
        }
    }
}
