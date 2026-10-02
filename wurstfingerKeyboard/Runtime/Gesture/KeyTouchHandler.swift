//
//  KeyTouchHandler.swift
//  Wurstfinger
//
//  SwiftUI adapter that runs one `KeyGestureSession` per touch on a key.
//

import QuartzCore
import SwiftUI

/// Runs scheduled gesture work on the main queue.
struct MainQueueGestureScheduler: GestureScheduler {
    private final class Work: GestureTimer {
        let item: DispatchWorkItem

        init(_ item: DispatchWorkItem) {
            self.item = item
        }

        func cancel() {
            item.cancel()
        }
    }

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> GestureTimer {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return Work(item)
    }
}

/// Feeds a key's touches into a fresh `KeyGestureSession` and reports the
/// resulting events.
struct KeyTouchHandler: ViewModifier {
    /// Builds the settings snapshot for a new touch.
    let makeConfig: () -> KeyGestureConfig
    /// Device pixels per point; gesture math runs in pixels like Thumb-Key.
    let pixelScale: CGFloat
    let onTouchDown: () -> Void
    let onEvent: (KeyGestureEvent) -> Void
    @Binding var isActive: Bool

    /// Reference box so the session survives view updates during a touch.
    private final class SessionBox {
        var session: KeyGestureSession?
    }

    @State private var box = SessionBox()
    /// Resets when the system cancels the touch, which never calls `onEnded`.
    @GestureState private var touching = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($touching) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    if box.session == nil {
                        let session = KeyGestureSession(
                            config: makeConfig(),
                            now: CACurrentMediaTime,
                            scheduler: MainQueueGestureScheduler(),
                            emit: onEvent
                        )
                        box.session = session
                        isActive = true
                        onTouchDown()
                        session.begin()
                    }
                    box.session?.move(to: CGPoint(
                        x: value.translation.width * pixelScale,
                        y: value.translation.height * pixelScale
                    ))
                }
                .onEnded { value in
                    if box.session == nil {
                        // A touch too quick for any onChanged still counts as a tap.
                        onTouchDown()
                        onEvent(.tap)
                    } else {
                        box.session?.move(to: CGPoint(
                            x: value.translation.width * pixelScale,
                            y: value.translation.height * pixelScale
                        ))
                        box.session?.end()
                    }
                    box.session = nil
                    isActive = false
                }
        )
        .onChange(of: touching) { isTouching in
            guard !isTouching, let session = box.session else { return }
            session.cancel()
            box.session = nil
            isActive = false
        }
    }
}
