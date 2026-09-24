//
//  SwipeGeometryTests.swift
//  WurstfingerTests
//
//  Thumb-Key's swipe direction zones, circle detection and slide speed.
//

import CoreGraphics
import Foundation
import Testing
@testable import WurstfingerApp

struct SwipeDirectionTests {
    private func direction(_ x: CGFloat, _ y: CGFloat, _ mode: SwipeMode = .eightWay) -> GestureType? {
        SwipeGeometry.direction(of: CGPoint(x: x, y: y), minSwipeLength: 40, swipeMode: mode)
    }

    @Test func shortOffsetHasNoDirection() {
        #expect(direction(30, 0) == nil)
        #expect(direction(40, 0) == nil, "Must be longer than the minimum, not equal")
        #expect(direction(41, 0) == .swipeRight)
    }

    @Test func eightWayMapsAllDirections() {
        #expect(direction(0, 100) == .swipeDown)
        #expect(direction(100, 100) == .swipeDownRight)
        #expect(direction(100, 0) == .swipeRight)
        #expect(direction(100, -100) == .swipeUpRight)
        #expect(direction(0, -100) == .swipeUp)
        #expect(direction(-100, -100) == .swipeUpLeft)
        #expect(direction(-100, 0) == .swipeLeft)
        #expect(direction(-100, 100) == .swipeDownLeft)
    }

    @Test func fourWayDiagonalWidensEachDiagonal() {
        // Anything between straight right and straight down is ↘.
        #expect(direction(100, 5, .fourWayDiagonal) == .swipeDownRight)
        #expect(direction(5, 100, .fourWayDiagonal) == .swipeDownRight)
        #expect(direction(100, -5, .fourWayDiagonal) == .swipeUpRight)
        #expect(direction(-5, -100, .fourWayDiagonal) == .swipeUpLeft)
        #expect(direction(-100, 5, .fourWayDiagonal) == .swipeDownLeft)
    }

    @Test func fourWayCrossUsesQuarterSectors() {
        #expect(direction(100, 90, .fourWayCross) == .swipeRight)
        #expect(direction(90, 100, .fourWayCross) == .swipeDown)
        #expect(direction(-100, -90, .fourWayCross) == .swipeLeft)
        #expect(direction(-90, -100, .fourWayCross) == .swipeUp)
    }

    @Test func twoWayModesUseHalfPlanes() {
        #expect(direction(10, -100, .twoWayHorizontal) == .swipeRight)
        #expect(direction(-10, 100, .twoWayHorizontal) == .swipeLeft)
        #expect(direction(100, -10, .twoWayVertical) == .swipeUp)
        #expect(direction(-100, 10, .twoWayVertical) == .swipeDown)
    }
}

struct CircularDirectionTests {
    /// Points on a circle starting at the top, sweeping `turns` full turns.
    /// Screen coordinates: y grows downwards, so increasing angle is clockwise.
    private func circle(radius: CGFloat, turns: CGFloat = 1, clockwise: Bool, steps: Int = 60) -> [CGPoint] {
        (0 ... steps).map { step in
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi * turns * (clockwise ? 1 : -1) - .pi / 2
            return CGPoint(x: radius * cos(angle), y: radius + radius * sin(angle))
        }
    }

    private func detect(_ points: [CGPoint]) -> CircularDirection? {
        SwipeGeometry.circularDirection(of: points, completionTolerance: 40 * 0.71, minSwipeLength: 40)
    }

    @Test func detectsClockwiseCircle() {
        #expect(detect(circle(radius: 60, clockwise: true)) == .clockwise)
    }

    @Test func detectsCounterclockwiseCircle() {
        #expect(detect(circle(radius: 60, clockwise: false)) == .counterclockwise)
    }

    @Test func rejectsHalfCircle() {
        #expect(detect(circle(radius: 60, turns: 0.5, clockwise: true)) == nil)
    }

    @Test func rejectsTinyCircle() {
        // Radius must exceed half the minimum swipe length.
        #expect(detect(circle(radius: 15, clockwise: true)) == nil)
    }

    @Test func rejectsStraightOutAndBack() {
        let out = (0 ... 20).map { CGPoint(x: CGFloat($0) * 5, y: 0) }
        let back = (0 ... 20).reversed().map { CGPoint(x: CGFloat($0) * 5, y: 0) }
        #expect(detect(out + back) == nil)
    }

    @Test func emptyInputHasNoCircle() {
        #expect(detect([]) == nil)
    }
}

struct SlideCursorDistanceTests {
    @Test func linearScalesWithSpeedAndSensitivity() {
        // 32 px in 16 ms = 2 px/ms; sensitivity 9 gives a 0.54 curve → 1 character.
        #expect(SwipeGeometry.slideCursorDistance(offsetX: 32, elapsedMilliseconds: 16, mode: .linear, sensitivity: 9) == 1)
        #expect(SwipeGeometry.slideCursorDistance(offsetX: -32, elapsedMilliseconds: 16, mode: .linear, sensitivity: 9) == -1)
        #expect(SwipeGeometry.slideCursorDistance(offsetX: 16, elapsedMilliseconds: 16, mode: .linear, sensitivity: 9) == 0)
    }

    @Test func noTimeMeansNoMovement() {
        #expect(SwipeGeometry.slideCursorDistance(offsetX: 100, elapsedMilliseconds: 0, mode: .linear, sensitivity: 50) == 0)
    }

    @Test func constantMovesOneCharacterPastThreshold() {
        // Threshold is 50 - sensitivity pixels.
        #expect(SwipeGeometry.slideCursorDistance(offsetX: 42, elapsedMilliseconds: 16, mode: .constant, sensitivity: 9) == 1)
        #expect(SwipeGeometry.slideCursorDistance(offsetX: 40, elapsedMilliseconds: 16, mode: .constant, sensitivity: 9) == 0)
        #expect(SwipeGeometry.slideCursorDistance(offsetX: -42, elapsedMilliseconds: 16, mode: .constant, sensitivity: 9) == -1)
    }

    @Test func quadraticAcceleratesFastSlides() {
        let slow = SwipeGeometry.slideCursorDistance(offsetX: 48, elapsedMilliseconds: 16, mode: .quadratic, sensitivity: 9)
        let fast = SwipeGeometry.slideCursorDistance(offsetX: 160, elapsedMilliseconds: 16, mode: .quadratic, sensitivity: 9)
        #expect(fast > slow * 3)
    }

    @Test func thresholdIsLinearBelowTwoPixelsPerMillisecond() {
        #expect(SwipeGeometry.slideCursorDistance(offsetX: 24, elapsedMilliseconds: 16, mode: .threshold, sensitivity: 9) == 1)
        #expect(SwipeGeometry.slideCursorDistance(offsetX: 160, elapsedMilliseconds: 16, mode: .threshold, sensitivity: 9) > 10)
    }
}
