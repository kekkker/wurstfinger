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
        /// Standard key height in points.
        /// Derived from iOS standard keyboard key height (~54pt) for comfortable touch targets.
        static let height: CGFloat = 54

        /// Minimum key width for accessibility compliance.
        /// Based on Apple's Human Interface Guidelines (44pt minimum touch target).
        static let minWidth: CGFloat = 44

        /// Reference key aspect ratio (width/height) at which `height` is defined.
        /// Used only as the baseline in `Calculations.keyHeight`; it is NOT the
        /// user-facing default setting (that is `DeviceLayoutUtils.defaultKeyAspectRatio`).
        static let referenceAspectRatio: CGFloat = 1.5

        /// Total number of rows in the keyboard layout.
        /// 3 rows for main keys + 1 row for space bar = 4 rows.
        static let totalRows: Int = 4
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
        /// Calculates the adjusted key height based on aspect ratio
        static func keyHeight(aspectRatio: CGFloat) -> CGFloat {
            KeyDimensions.height * (KeyDimensions.referenceAspectRatio / aspectRatio)
        }

        /// Calculates the total keyboard base height (without scaling)
        static func baseHeight(aspectRatio: CGFloat) -> CGFloat {
            let keyHeight = keyHeight(aspectRatio: aspectRatio)
            return (keyHeight * CGFloat(KeyDimensions.totalRows)) +
                (Layout.gridVerticalSpacing * CGFloat(KeyDimensions.totalRows - 1)) +
                Layout.verticalPaddingTop + Layout.verticalPaddingBottom +
                Layout.spellcheckBarHeight
        }

        /// Height of the keyboard exactly as rendered by SwiftUI.
        ///
        /// Key views scale with `keyboardScale`, while grid spacing and outer
        /// padding remain fixed point values. Scaling `baseHeight` as a whole
        /// makes the host view too short whenever scale is below 1, clipping
        /// the top row by the unallocated fixed spacing.
        static func renderedHeight(aspectRatio: CGFloat, scale: CGFloat) -> CGFloat {
            let scaledKeys = keyHeight(aspectRatio: aspectRatio) *
                scale * CGFloat(KeyDimensions.totalRows)
            let fixedSpacing = Layout.gridVerticalSpacing *
                CGFloat(KeyDimensions.totalRows - 1)
            return scaledKeys + fixedSpacing +
                Layout.verticalPaddingTop + Layout.verticalPaddingBottom +
                Layout.spellcheckBarHeight
        }
    }
}
