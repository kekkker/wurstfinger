//
//  KeyGestureSessionTests.swift
//  WurstfingerTests
//
//  One touch on one key, classified like Thumb-Key's KeyboardKey.
//

import CoreGraphics
import Foundation
import Testing
@testable import WurstfingerApp

/// Runs scheduled work only when the test advances time.
final class ManualGestureScheduler: GestureScheduler {
    private final class Work: GestureTimer {
        let due: TimeInterval
        let block: () -> Void
        var cancelled = false

        init(due: TimeInterval, block: @escaping () -> Void) {
            self.due = due
            self.block = block
        }

        func cancel() {
            cancelled = true
        }
    }

    private(set) var now: TimeInterval = 0
    private var pending: [Work] = []

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> GestureTimer {
        let item = Work(due: now + delay, block: work)
        pending.append(item)
        return item
    }

    /// Moves time forward, running everything that becomes due in order.
    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let next = pending.filter({ !$0.cancelled && $0.due <= target }).min(by: { $0.due < $1.due }) {
            pending.removeAll { $0 === next }
            now = next.due
            next.block()
        }
        now = target
    }
}

private final class EventRecorder {
    var events: [KeyGestureEvent] = []
}

private final class SessionHarness {
    let scheduler: ManualGestureScheduler
    let session: KeyGestureSession
    private let recorder: EventRecorder

    init(_ config: KeyGestureConfig = KeyGestureConfig()) {
        let scheduler = ManualGestureScheduler()
        let recorder = EventRecorder()
        self.scheduler = scheduler
        self.recorder = recorder
        session = KeyGestureSession(
            config: config,
            now: { scheduler.now },
            scheduler: scheduler,
            emit: { recorder.events.append($0) }
        )
    }

    var emitted: [KeyGestureEvent] {
        recorder.events
    }

    /// Drags through `points` (translations from touch-down), one per 16 ms.
    func drag(_ points: [CGPoint]) {
        for point in points {
            scheduler.advance(by: 0.016)
            session.move(to: point)
        }
    }

    var outcome: DragOutcome? {
        for case let .drag(outcome) in emitted {
            return outcome
        }
        return nil
    }
}

/// A straight path from the origin to `end`.
private func line(to end: CGPoint, steps: Int = 10) -> [CGPoint] {
    (1 ... steps).map { step in
        CGPoint(x: end.x * CGFloat(step) / CGFloat(steps), y: end.y * CGFloat(step) / CGFloat(steps))
    }
}

struct KeyGestureSessionTapTests {
    @Test func stillTouchIsATap() {
        let harness = SessionHarness()
        harness.session.begin()
        harness.session.move(to: CGPoint(x: 3, y: 2))
        harness.session.end()
        #expect(harness.emitted == [.tap])
    }

    @Test func movementBeyondSlopIsADrag() {
        let harness = SessionHarness()
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: 120, y: 0)))
        harness.session.end()
        #expect(harness.outcome?.finalDirection == .swipeRight)
        #expect(harness.outcome?.isReturn == false)
    }

    @Test func shortDragHasNoDirection() {
        // Past the slop but not past slop + minimum swipe length.
        let harness = SessionHarness()
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: 50, y: 0)))
        harness.session.end()
        #expect(harness.outcome?.finalDirection == nil)
    }

    @Test func minimumSwipeIsMeasuredBeyondTheSlop() {
        // Slop 24 + minimum 40: 60 px is not enough, 70 px is.
        let short = SessionHarness()
        short.session.begin()
        short.drag(line(to: CGPoint(x: 60, y: 0)))
        short.session.end()
        #expect(short.outcome?.finalDirection == nil)

        let long = SessionHarness()
        long.session.begin()
        long.drag(line(to: CGPoint(x: 70, y: 0)))
        long.session.end()
        #expect(long.outcome?.finalDirection == .swipeRight)
    }
}

struct KeyGestureSessionLongPressTests {
    @Test func holdFiresLongPressAndSuppressesTap() {
        var config = KeyGestureConfig()
        config.hasLongPress = true
        let harness = SessionHarness(config)
        harness.session.begin()
        harness.scheduler.advance(by: 0.5)
        harness.session.end()
        #expect(harness.emitted == [.longPress])
    }

    @Test func holdWithoutLongPressBindingIsATap() {
        let harness = SessionHarness()
        harness.session.begin()
        harness.scheduler.advance(by: 0.5)
        harness.session.end()
        #expect(harness.emitted == [.tap])
    }

    @Test func dragCancelsLongPress() {
        var config = KeyGestureConfig()
        config.hasLongPress = true
        let harness = SessionHarness(config)
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: -120, y: 0)))
        harness.scheduler.advance(by: 1)
        harness.session.end()
        #expect(!harness.emitted.contains(.longPress))
        #expect(harness.outcome?.finalDirection == .swipeLeft)
    }
}

struct KeyGestureSessionReturnTests {
    @Test func outAndBackIsAReturn() {
        let harness = SessionHarness()
        harness.session.begin()
        let out = line(to: CGPoint(x: 0, y: -120))
        harness.drag(out + out.reversed().dropFirst() + [CGPoint(x: 0, y: -2)])
        harness.session.end()
        #expect(harness.outcome?.isReturn == true)
        #expect(harness.outcome?.maxDirection == .swipeUp)
        #expect(harness.outcome?.circular == nil)
    }

    @Test func endingInAnotherDirectionCountsAsReturn() {
        let harness = SessionHarness()
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: 0, y: -150)) + [CGPoint(x: 60, y: -100), CGPoint(x: 90, y: -40)])
        harness.session.end()
        #expect(harness.outcome?.isReturn == true)
        #expect(harness.outcome?.maxDirection == .swipeUp)
    }

    @Test func circleIsDetected() {
        let harness = SessionHarness()
        harness.session.begin()
        let points = (1 ... 40).map { step -> CGPoint in
            let angle = CGFloat(step) / 40 * 2 * .pi - .pi / 2
            return CGPoint(x: 80 * cos(angle), y: 80 + 80 * sin(angle))
        }
        harness.drag(points)
        harness.session.end()
        #expect(harness.outcome?.isReturn == true)
        #expect(harness.outcome?.circular == .clockwise)
    }

    @Test func circlesCanBeDisabled() {
        var config = KeyGestureConfig()
        config.circularDragEnabled = false
        let harness = SessionHarness(config)
        harness.session.begin()
        let points = (1 ... 40).map { step -> CGPoint in
            let angle = CGFloat(step) / 40 * 2 * .pi - .pi / 2
            return CGPoint(x: 80 * cos(angle), y: 80 + 80 * sin(angle))
        }
        harness.drag(points)
        harness.session.end()
        #expect(harness.outcome?.circular == nil)
    }

    @Test func directionUsesTheKeysZones() {
        var config = KeyGestureConfig()
        config.swipeMode = .fourWayDiagonal
        config.directionMode = .fourWayDiagonal
        let harness = SessionHarness(config)
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: 150, y: 10)))
        harness.session.end()
        #expect(harness.outcome?.finalDirection == .swipeDownRight)
    }
}

struct KeyGestureSessionSlideTests {
    private func spaceConfig(deadzone: Bool = true) -> KeyGestureConfig {
        var config = KeyGestureConfig()
        config.slideType = .moveCursor
        config.slideEnabled = true
        config.spacebarDeadzone = deadzone
        config.keySize = 180
        config.cursorMode = .constant
        return config
    }

    @Test func slideOffStillSwipes() {
        var config = spaceConfig()
        config.slideEnabled = false
        let harness = SessionHarness(config)
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: -400, y: 0), steps: 20))
        harness.session.end()
        #expect(harness.outcome?.finalDirection == .swipeLeft)
    }

    @Test func shortSwipeInsideDeadzoneStaysASwipe() {
        let harness = SessionHarness(spaceConfig())
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: 120, y: 0)))
        harness.session.end()
        #expect(harness.outcome?.finalDirection == .swipeRight)
        #expect(!harness.emitted.contains {
            if case .slideCursor = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func slidePastDeadzoneMovesCursor() {
        let harness = SessionHarness(spaceConfig())
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: 600, y: 0), steps: 30))
        harness.session.end()
        let moves = harness.emitted.compactMap {
            if case let .slideCursor(n) = $0 {
                n
            } else {
                nil
            }
        }
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0 > 0 })
        #expect(harness.outcome == nil, "A finished slide types nothing")
    }

    @Test func backspaceSlideSelectsThenDeletes() {
        var config = spaceConfig()
        config.slideType = .delete
        config.backspaceDeadzone = false
        let harness = SessionHarness(config)
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: -600, y: 0), steps: 30))
        harness.session.end()
        #expect(harness.emitted.first == .selectionBegan)
        #expect(harness.emitted.contains {
            if case let .selectionChanged(n) = $0 {
                n < 0
            } else {
                false
            }
        })
        #expect(harness.emitted.last == .deleteSelection)
    }

    @Test func slideHoldRepeatsUntilRelease() {
        var config = KeyGestureConfig()
        config.slideType = .delete
        config.slideHoldEnabled = true
        let harness = SessionHarness(config)
        harness.session.begin()
        // The hold is detected at 112 ms; ticks follow every 300 ms, then every 100 ms.
        harness.drag(line(to: CGPoint(x: -100, y: 0)))
        let tick = KeyGestureEvent.slideHoldTick(.swipeLeft, word: false)
        harness.scheduler.advance(by: 1.25)
        #expect(harness.emitted.filter { $0 == tick }.count == 4)
        harness.scheduler.advance(by: 0.25)
        #expect(harness.emitted.filter { $0 == tick }.count == 7)
        harness.session.end()
        harness.scheduler.advance(by: 1)
        #expect(harness.emitted.filter { $0 == tick }.count == 7, "Release stops the repeats")
        #expect(harness.outcome == nil, "Release after repeats does nothing more")
    }

    @Test func slideHoldReleasedEarlyIsASwipe() {
        var config = KeyGestureConfig()
        config.slideType = .delete
        config.slideHoldEnabled = true
        let harness = SessionHarness(config)
        harness.session.begin()
        harness.drag(line(to: CGPoint(x: -100, y: 0)))
        harness.session.end()
        harness.scheduler.advance(by: 1)
        #expect(harness.outcome?.finalDirection == .swipeLeft)
        #expect(!harness.emitted.contains(.slideHoldTick(.swipeLeft, word: false)))
    }
}
