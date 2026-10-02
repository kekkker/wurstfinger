//
//  SwipeGeometry.swift
//  Wurstfinger
//
//  Thumb-Key's swipe, circle and slide math, ported 1:1 from
//  `utils/Utils.kt` so gestures feel identical to the Android keyboard.
//  All distances are in device pixels, like Thumb-Key's.
//

import CoreGraphics
import Foundation

/// Rotation direction of a circular drag.
enum CircularDirection: Equatable {
    case clockwise
    case counterclockwise
}

/// Cursor speed curve used while sliding on the space bar or backspace.
/// Raw values are persisted.
enum SlideCursorMovementMode: String, CaseIterable {
    case linear
    case quadratic
    case threshold
    case constant
}

enum SwipeGeometry {
    /// Thumb-Key's `DRAG_RETURN_THRESHOLD_FACTOR`: how close to its origin a
    /// finger must come back (relative to the minimum swipe length) for a
    /// swipe to count as swipe-and-return. Also the circle completion
    /// tolerance factor.
    static let dragReturnThresholdFactor: CGFloat = 0.71

    // MARK: - Direction

    /// The swipe direction of `offset` for a key restricted to `swipeMode`,
    /// or `nil` when the offset is not longer than `minSwipeLength`.
    ///
    /// Reduced swipe modes widen each direction's sector: on a
    /// `.fourWayDiagonal` key any drag between straight right and straight
    /// down counts as ↘.
    static func direction(of offset: CGPoint, minSwipeLength: CGFloat, swipeMode: SwipeMode) -> GestureType? {
        let length = hypot(offset.x, offset.y)
        guard length > minSwipeLength else { return nil }

        // 0° = down, increasing counter-clockwise (towards the right), as in Thumb-Key.
        var angle = atan2(offset.x, offset.y) * 180 / .pi
        if angle < 0 {
            angle += 360
        }

        switch swipeMode {
        case .eightWay, .none:
            return eightWayDirection(angle)
        case .fourWayCross:
            return fourWayCrossDirection(angle)
        case .fourWayDiagonal:
            return fourWayDiagonalDirection(angle)
        case .twoWayHorizontal:
            return (0 ... 180).contains(angle) ? .swipeRight : .swipeLeft
        case .twoWayVertical:
            return (90 ... 270).contains(angle) ? .swipeUp : .swipeDown
        }
    }

    // Sector tables use Thumb-Key's inclusive ranges; the first match wins.

    private static func eightWayDirection(_ angle: CGFloat) -> GestureType {
        let sectors: [(ClosedRange<CGFloat>, GestureType)] = [
            (22.5 ... 67.5, .swipeDownRight),
            (67.5 ... 112.5, .swipeRight),
            (112.5 ... 157.5, .swipeUpRight),
            (157.5 ... 202.5, .swipeUp),
            (202.5 ... 247.5, .swipeUpLeft),
            (247.5 ... 292.5, .swipeLeft),
            (292.5 ... 337.5, .swipeDownLeft),
        ]
        return sectors.first { $0.0.contains(angle) }?.1 ?? .swipeDown
    }

    private static func fourWayCrossDirection(_ angle: CGFloat) -> GestureType {
        let sectors: [(ClosedRange<CGFloat>, GestureType)] = [
            (45 ... 135, .swipeRight),
            (135 ... 225, .swipeUp),
            (225 ... 315, .swipeLeft),
        ]
        return sectors.first { $0.0.contains(angle) }?.1 ?? .swipeDown
    }

    private static func fourWayDiagonalDirection(_ angle: CGFloat) -> GestureType {
        let sectors: [(ClosedRange<CGFloat>, GestureType)] = [
            (0 ... 90, .swipeDownRight),
            (90 ... 180, .swipeUpRight),
            (180 ... 270, .swipeUpLeft),
        ]
        return sectors.first { $0.0.contains(angle) }?.1 ?? .swipeDownLeft
    }

    // MARK: - Circles

    /// Detects a circular drag in `positions` (offsets from the drag start).
    ///
    /// Run-up points that keep getting closer to the end point are dropped
    /// first, so spiralling circles with an offset start still count. The
    /// circle must keep a minimum radius of half the swipe length, and the
    /// signed angle it sweeps around its centroid must reach almost a full
    /// turn (less the completion tolerance relative to its radius).
    static func circularDirection(
        of positions: [CGPoint],
        completionTolerance: CGFloat,
        minSwipeLength: CGFloat
    ) -> CircularDirection? {
        guard let last = positions.last else { return nil }

        var firstKept = positions.count
        for index in positions.indices {
            let approaching = index == 0
                || distance(positions[index], last) <= distance(positions[index - 1], last)
            if !approaching {
                firstKept = index
                break
            }
        }
        let points = Array(positions[firstKept...])
        guard !points.isEmpty else { return nil }

        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let center = CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        let radii = points.map { distance($0, center) }
        guard let minRadius = radii.min(), let maxRadius = radii.max(),
              minRadius > minSwipeLength / 2
        else { return nil }

        var spannedAngle: CGFloat = 0
        for index in points.indices.dropFirst() {
            let a = CGPoint(x: points[index - 1].x - center.x, y: points[index - 1].y - center.y)
            let b = CGPoint(x: points[index].x - center.x, y: points[index].y - center.y)
            spannedAngle += atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
        }

        let averageRadius = (minRadius + maxRadius) / 2
        let angleThreshold = 2 * .pi * (1 - completionTolerance / averageRadius)

        if spannedAngle >= angleThreshold {
            return .clockwise
        }
        if spannedAngle <= -angleThreshold {
            return .counterclockwise
        }
        return nil
    }

    // MARK: - Slide Cursor Distance

    /// Number of characters to move for a slide step, from Thumb-Key's
    /// `slideCursorDistance`.
    ///
    /// - Parameters:
    ///   - offsetX: Horizontal travel (px) since the last cursor move.
    ///   - elapsedMilliseconds: Time since the previous slide input.
    ///   - mode: Speed curve.
    ///   - sensitivity: User setting, 1–50.
    static func slideCursorDistance(
        offsetX: CGFloat,
        elapsedMilliseconds: Double,
        mode: SlideCursorMovementMode,
        sensitivity: Int
    ) -> Int {
        if mode == .constant {
            let sliderMaximum: CGFloat = 50
            guard abs(offsetX) > sliderMaximum - CGFloat(sensitivity) else { return 0 }
            return offsetX > 0 ? 1 : -1
        }

        let speed = elapsedMilliseconds == 0 ? 0 : Double(abs(offsetX)) / elapsedMilliseconds
        let sensitivity = Double(sensitivity)
        var distance: Double
        switch mode {
        case .linear, .constant:
            distance = speed * (sensitivity * 6 / 100)
        case .quadratic:
            distance = (0.1 + sensitivity * 6 / 1000) * speed * speed
        case .threshold:
            let exponent = 1 + sensitivity * 4 / 100
            let threshold = 2.0
            let belowThreshold = min(speed, threshold)
            distance = pow(max(0, speed - belowThreshold), exponent) + belowThreshold
        }
        if offsetX < 0 {
            distance = -distance
        }
        return Int(distance)
    }

    // MARK: - Helpers

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
