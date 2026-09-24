//
//  OppositeCaseResolver.swift
//  Wurstfinger
//
//  Resolver for swipe-and-return without an explicit return action: types
//  what the same swipe types on the opposite-case layer.
//

import Foundation

/// Thumb-Key's swipe-and-return fallback: the same key and direction on the
/// opposite-case layer (shifted while typing lowercase, and vice versa), so
/// returning a letter swipe types that letter in the other case.
struct OppositeCaseResolver: GestureResolver {
    let oppositeMode: KeyboardMode

    func resolve(keyId: String, gesture: GestureType, in _: KeyboardMode) -> KeyBinding? {
        guard gesture.isSwipe else { return nil }
        return oppositeMode.key(for: keyId)?.bindings[gesture]
    }
}
