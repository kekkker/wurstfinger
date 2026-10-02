//
//  KeyboardConstants.swift
//  Wurstfinger
//
//  Shared constants for keyboard dimensions, font sizes, and gesture thresholds.
//

import CoreGraphics
import Foundation

enum KeyboardConstants {
    // MARK: - Key Dimensions

    enum KeyDimensions {
        /// Minimum key width for accessibility compliance.
        /// Based on Apple's Human Interface Guidelines (44pt minimum touch target).
        static let minWidth: CGFloat = 44

        /// Rows and columns of the portrait layout (3 letter rows plus the
        /// space bar row; 3 letter columns plus the utility column).
        static let totalRows: Int = 4
        static let totalColumns: Int = 4
    }

    // MARK: - Layout Spacing

    enum Layout {
        /// Horizontal gap between grid cells. Keys fill their cells like
        /// Thumb-Key's; the visible gap comes from the key padding setting.
        static let gridHorizontalSpacing: CGFloat = 0
        /// Vertical gap between key rows.
        static let gridVerticalSpacing: CGFloat = 0
        /// Left/right padding of the entire keyboard.
        static let horizontalPadding: CGFloat = 0
        /// Top padding - minimal since keyboard sits directly below text input.
        static let verticalPaddingTop: CGFloat = 0
        /// Bottom padding; the controller already reserves a gap below the keys.
        static let verticalPaddingBottom: CGFloat = 0
        /// Compact status and correction row above the key grid.
        static let spellcheckBarHeight: CGFloat = 32
        /// Space above the keys when Thumb-Key's keyboard backdrop is on.
        static let backdropTopPadding: CGFloat = 6
        /// Margin for hint labels from key edges.
        static let hintMargin: CGFloat = 10
        /// Larger margin for "returning" hint labels (swipe-and-return gestures).
        static let hintMarginReturning: CGFloat = 22
    }

    // MARK: - Gesture Recognition

    enum Gesture {
        /// Distance a finger must move before a touch becomes a drag
        /// (Android's 8 dp touch slop, which Thumb-Key inherits).
        static let touchSlop: CGFloat = 8
    }

    // MARK: - Preview Settings

    enum Preview {
        /// Minimum height for keyboard preview in settings.
        static let minHeight: CGFloat = 100
        /// Maximum height for keyboard preview in settings.
        static let maxHeight: CGFloat = 400
    }

    // MARK: - Keyboard Calculations

    enum Calculations {
        /// Width of the key grid: the screen's short side times the scale (so
        /// landscape keeps the portrait key width), or at most half the view
        /// per copy when the keyboard is split.
        static func gridWidth(viewWidth: CGFloat, screenShortestSide: CGFloat, scale: CGFloat, split: Bool) -> CGFloat {
            let scaled = min(viewWidth, screenShortestSide) * scale
            return split ? min(scaled, viewWidth / 2) : scaled
        }

        /// Key height from the key width, like Thumb-Key: one grid column wide,
        /// and as tall as the width divided by the aspect ratio (1.0 = square).
        static func keyHeight(gridWidth: CGFloat, columns: Int, aspectRatio: CGFloat) -> CGFloat {
            gridWidth / CGFloat(max(columns, 1)) / max(aspectRatio, 0.1)
        }

        /// Height of the keyboard exactly as rendered by SwiftUI: the key rows
        /// (the current arrangement's count; landscape has 3), the fixed grid
        /// spacing and padding, and the spellcheck bar.
        static func renderedHeight(keyHeight: CGFloat, rows: Int = KeyDimensions.totalRows) -> CGFloat {
            keyHeight * CGFloat(rows) +
                Layout.gridVerticalSpacing * CGFloat(rows - 1) +
                Layout.verticalPaddingTop + Layout.verticalPaddingBottom +
                Layout.spellcheckBarHeight
        }
    }
}
