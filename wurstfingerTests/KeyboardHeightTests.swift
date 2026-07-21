//
//  KeyboardHeightTests.swift
//  wurstfingerTests
//

import Foundation
import Testing
@testable import WurstfingerApp

struct KeyboardHeightTests {
    @Test("Full-scale rendered height matches the base height")
    func fullScaleMatchesBaseHeight() {
        let aspectRatio: CGFloat = 1.25
        let rendered = KeyboardConstants.Calculations.renderedHeight(
            aspectRatio: aspectRatio,
            scale: 1
        )

        #expect(abs(rendered - KeyboardConstants.Calculations.baseHeight(
            aspectRatio: aspectRatio
        )) < 0.0001)
    }

    @Test("Compact height scales keys but preserves fixed layout spacing")
    func compactHeightPreservesFixedSpacing() {
        let aspectRatio: CGFloat = 1.25
        let scale: CGFloat = 0.5
        let rowCount = CGFloat(KeyboardConstants.KeyDimensions.totalRows)
        let scaledKeys = KeyboardConstants.Calculations.keyHeight(
            aspectRatio: aspectRatio
        ) * scale * rowCount
        let fixedSpacing = KeyboardConstants.Layout.gridVerticalSpacing *
            CGFloat(KeyboardConstants.KeyDimensions.totalRows - 1) +
            KeyboardConstants.Layout.verticalPaddingTop +
            KeyboardConstants.Layout.verticalPaddingBottom +
            KeyboardConstants.Layout.spellcheckBarHeight

        let rendered = KeyboardConstants.Calculations.renderedHeight(
            aspectRatio: aspectRatio,
            scale: scale
        )

        #expect(abs(rendered - (scaledKeys + fixedSpacing)) < 0.0001)
        #expect(rendered > KeyboardConstants.Calculations.baseHeight(
            aspectRatio: aspectRatio
        ) * scale)
    }
}
