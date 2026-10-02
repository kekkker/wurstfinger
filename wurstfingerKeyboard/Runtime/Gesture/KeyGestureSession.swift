//
//  KeyGestureSession.swift
//  Wurstfinger
//
//  One touch on one key, classified exactly like Thumb-Key's `KeyboardKey`:
//  tap, long press, swipe, swipe-and-return, circle, and the space/backspace
//  slide and slide-hold gestures. UI-free so it can be unit tested; the
//  SwiftUI side (`KeyTouchHandler`) only feeds it translations.
//

import CoreGraphics
import Foundation

/// Settings snapshot for one touch session. Distances are in device pixels.
struct KeyGestureConfig: Equatable {
    /// The key's own swipe restriction (used for swipe-and-return detection).
    var swipeMode: SwipeMode = .eightWay
    /// Mode used to bin swipe directions. Thumb-Key widens this to 8-way when
    /// a ghost key sits behind the key.
    var directionMode: SwipeMode = .eightWay
    var slideType: SlideType = .none
    var minSwipeLength: CGFloat = 40
    /// Distance a finger must travel before a touch becomes a drag.
    var touchSlop: CGFloat = 24
    /// Average of key width and height.
    var keySize: CGFloat = 180
    var hasLongPress = false
    var longPressDelay: TimeInterval = 0.4
    var circularDragEnabled = true
    var slideEnabled = false
    var slideHoldEnabled = false
    var spacebarDeadzone = true
    var backspaceDeadzone = true
    var cursorMode: SlideCursorMovementMode = .linear
    var slideSensitivity = 9
}

/// Result of a finished drag, before the keyboard maps it to an action.
struct DragOutcome: Equatable {
    /// Direction of the final offset, if long enough.
    let finalDirection: GestureType?
    /// Direction of the farthest point reached, if long enough.
    let maxDirection: GestureType?
    /// The finger went out at least a swipe length and came back.
    let isReturn: Bool
    /// Set for a returning drag that traced a circle.
    let circular: CircularDirection?
}

/// What a touch amounts to. Emitted while the touch is in progress (long
/// press, slides) or when it ends (tap, drag).
enum KeyGestureEvent: Equatable {
    case tap
    case longPress
    case drag(DragOutcome)
    /// Space slide: move the cursor by this many characters.
    case slideCursor(Int)
    /// A slide started selecting text at the cursor.
    case selectionBegan
    /// Total selection offset from where the selection began.
    case selectionChanged(Int)
    /// Leave the selection, keeping the cursor at its start or end.
    case selectionCollapsed(toEnd: Bool)
    /// A backspace slide ended: delete the selection.
    case deleteSelection
    /// Slide-hold repeat tick. `word` is set once the finger came back.
    case slideHoldTick(GestureType, word: Bool)
}

/// A cancellable piece of scheduled work.
protocol GestureTimer {
    func cancel()
}

/// Schedules delayed work for long presses and slide-hold repeats.
protocol GestureScheduler {
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> GestureTimer
}

final class KeyGestureSession {
    // Thumb-Key's slide-hold timing: 4 slow ticks, then fast ones.
    static let slideHoldSlowTickCount = 4
    static let slideHoldSlowTickDelay: TimeInterval = 0.3
    static let slideHoldFastTickDelay: TimeInterval = 0.1

    private let config: KeyGestureConfig
    private let now: () -> TimeInterval
    private let scheduler: GestureScheduler
    private let emit: (KeyGestureEvent) -> Void

    private var dragStarted = false
    private var lastTranslation = CGPoint.zero
    private var offset = CGPoint.zero
    private var maxOffset = CGPoint.zero
    private var positions: [CGPoint] = []

    private var longPressTimer: GestureTimer?
    private var longPressFired = false

    private var cursorSlideTriggered = false
    private var selectionActive = false
    private var selectionOffset = 0
    private var lastSlideInput: TimeInterval = 0

    private var slideHoldDirection: GestureType?
    private var slideHoldReturnDetected = false
    private var slideHoldTicks = 0
    private var slideHoldTimer: GestureTimer?

    private var finished = false

    init(
        config: KeyGestureConfig,
        now: @escaping () -> TimeInterval,
        scheduler: GestureScheduler,
        emit: @escaping (KeyGestureEvent) -> Void
    ) {
        self.config = config
        self.now = now
        self.scheduler = scheduler
        self.emit = emit
    }

    // MARK: - Touch Lifecycle

    /// Finger down.
    func begin() {
        guard config.hasLongPress else { return }
        longPressTimer = scheduler.schedule(after: config.longPressDelay) { [weak self] in
            guard let self, !dragStarted, !finished else { return }
            longPressFired = true
            emit(.longPress)
        }
    }

    /// Finger moved; `translation` is the total movement since touch-down.
    func move(to translation: CGPoint) {
        guard !finished, !longPressFired else { return }
        if !dragStarted {
            let distance = hypot(translation.x, translation.y)
            guard distance > config.touchSlop else { return }
            dragStarted = true
            longPressTimer?.cancel()
            // Like Compose's drag detector, offsets start at the slop boundary:
            // the first delta is only the movement beyond the touch slop.
            let slopPoint = CGPoint(
                x: translation.x / distance * config.touchSlop,
                y: translation.y / distance * config.touchSlop
            )
            lastTranslation = slopPoint
        }
        let delta = CGPoint(x: translation.x - lastTranslation.x, y: translation.y - lastTranslation.y)
        lastTranslation = translation
        drag(by: delta)
    }

    /// Finger lifted.
    func end() {
        guard !finished else { return }
        finished = true
        longPressTimer?.cancel()
        guard !longPressFired else { return }
        guard dragStarted else {
            emit(.tap)
            return
        }
        finishDrag()
    }

    /// Touch cancelled by the system; nothing fires.
    func cancel() {
        finished = true
        longPressTimer?.cancel()
        slideHoldTimer?.cancel()
    }

    // MARK: - Drag

    private func drag(by delta: CGPoint) {
        offset.x += delta.x
        offset.y += delta.y
        positions.append(offset)
        if lengthSquared(offset) > lengthSquared(maxOffset) {
            maxOffset = offset
        }

        guard config.slideType != .none else { return }
        if config.slideHoldEnabled {
            handleSlideHold()
        } else if config.slideEnabled {
            switch config.slideType {
            case .moveCursor: handleCursorSlide()
            case .delete: handleDeleteSlide()
            case .none: break
            }
        }
    }

    private var slideTrigger: CGFloat {
        config.keySize * 0.75 + config.minSwipeLength
    }

    private func handleCursorSlide() {
        let selectionTrigger = config.keySize * 1.25 + config.minSwipeLength
        if abs(offset.y) > selectionTrigger {
            // Sliding up or down past the key selects text.
            cursorSlideTriggered = true
            if !selectionActive {
                selectionActive = true
                selectionOffset = 0
                emit(.selectionBegan)
            }
            let movement = nextSlideDistance()
            if movement != 0 {
                selectionOffset += movement
                emit(.selectionChanged(selectionOffset))
                offset.x = 0
            }
            return
        }

        let pastDeadzone = abs(offset.x) > slideTrigger
        guard cursorSlideTriggered || !config.spacebarDeadzone || pastDeadzone else { return }
        if !cursorSlideTriggered {
            offset.x = 0
            cursorSlideTriggered = true
        }
        if selectionActive {
            selectionActive = false
            emit(.selectionCollapsed(toEnd: offset.x >= 0))
        }
        let movement = nextSlideDistance()
        if movement != 0 {
            emit(.slideCursor(movement))
            offset.x = 0
        }
    }

    private func handleDeleteSlide() {
        if !selectionActive {
            lastSlideInput = now()
            if !config.backspaceDeadzone || abs(offset.x) > slideTrigger {
                offset.x = 0
                selectionActive = true
                selectionOffset = 0
                emit(.selectionBegan)
            }
            return
        }
        let movement = nextSlideDistance()
        if movement != 0 {
            selectionOffset += movement
            emit(.selectionChanged(selectionOffset))
            offset.x = 0
        }
    }

    /// Characters to move for the travel since the last move.
    private func nextSlideDistance() -> Int {
        let time = now()
        let elapsed = (time - lastSlideInput) * 1000
        lastSlideInput = time
        return SwipeGeometry.slideCursorDistance(
            offsetX: offset.x,
            elapsedMilliseconds: elapsed,
            mode: config.cursorMode,
            sensitivity: config.slideSensitivity
        )
    }

    // MARK: - Slide Hold

    private func handleSlideHold() {
        let returnThreshold = config.minSwipeLength * SwipeGeometry.dragReturnThresholdFactor

        guard slideHoldDirection == nil else {
            guard !slideHoldReturnDetected, length(maxOffset) >= config.minSwipeLength else { return }
            let current = positions.last ?? offset
            let closeEnough = length(current) <= returnThreshold
            let currentDirection = SwipeGeometry.direction(
                of: current, minSwipeLength: config.minSwipeLength, swipeMode: .fourWayCross
            )
            let maxDirection = SwipeGeometry.direction(
                of: maxOffset, minSwipeLength: config.minSwipeLength, swipeMode: .fourWayCross
            )
            if closeEnough || currentDirection != maxDirection {
                slideHoldReturnDetected = true
            }
            return
        }

        guard let direction = SwipeGeometry.direction(
            of: offset, minSwipeLength: config.minSwipeLength, swipeMode: .fourWayCross
        ) else { return }
        slideHoldDirection = direction

        let repeats = switch config.slideType {
        case .moveCursor: direction == .swipeLeft || direction == .swipeRight
        case .delete: direction == .swipeLeft
        case .none: false
        }
        if repeats {
            scheduleSlideHoldTick(direction)
        }
    }

    private func scheduleSlideHoldTick(_ direction: GestureType) {
        let delay = slideHoldTicks < Self.slideHoldSlowTickCount
            ? Self.slideHoldSlowTickDelay
            : Self.slideHoldFastTickDelay
        slideHoldTimer = scheduler.schedule(after: delay) { [weak self] in
            guard let self, !finished else { return }
            emit(.slideHoldTick(direction, word: slideHoldReturnDetected))
            slideHoldTicks += 1
            scheduleSlideHoldTick(direction)
        }
    }

    // MARK: - Drag End

    private func finishDrag() {
        slideHoldTimer?.cancel()
        let isSlideKey = config.slideType != .none

        if isSlideKey, config.slideHoldEnabled, slideHoldTicks > 0 {
            // The repeats already did the work.
            return
        }

        let resolvesAsSwipe = !isSlideKey
            || !config.slideEnabled
            || config.slideHoldEnabled
            || (config.slideType == .delete && !selectionActive)
            || (config.slideType == .moveCursor && !cursorSlideTriggered)
        if resolvesAsSwipe {
            emit(.drag(outcome()))
        } else if config.slideType == .delete {
            emit(.deleteSelection)
        }
    }

    /// Thumb-Key's `onDragEnd` classification.
    func outcome() -> DragOutcome {
        let minSwipe = config.minSwipeLength
        let returnThreshold = minSwipe * SwipeGeometry.dragReturnThresholdFactor
        let finalOffset = positions.last ?? .zero

        // Coming back counts when the finger ends near the origin, or ends up
        // in a different direction than the farthest point it reached.
        let finalDirection = SwipeGeometry.direction(of: finalOffset, minSwipeLength: minSwipe, swipeMode: config.swipeMode)
        let farthestDirection = SwipeGeometry.direction(of: maxOffset, minSwipeLength: minSwipe, swipeMode: config.swipeMode)
        let finalSmallEnough = length(finalOffset) <= returnThreshold
            || finalDirection == nil
            || finalDirection != farthestDirection
        let isReturn = length(maxOffset) >= minSwipe && finalSmallEnough

        let circular = isReturn && config.circularDragEnabled
            ? SwipeGeometry.circularDirection(of: positions, completionTolerance: returnThreshold, minSwipeLength: minSwipe)
            : nil

        return DragOutcome(
            finalDirection: SwipeGeometry.direction(of: offset, minSwipeLength: minSwipe, swipeMode: config.directionMode),
            maxDirection: SwipeGeometry.direction(of: maxOffset, minSwipeLength: minSwipe, swipeMode: config.directionMode),
            isReturn: isReturn,
            circular: circular
        )
    }

    // MARK: - Helpers

    private func length(_ point: CGPoint) -> CGFloat {
        hypot(point.x, point.y)
    }

    private func lengthSquared(_ point: CGPoint) -> CGFloat {
        point.x * point.x + point.y * point.y
    }
}
