//
//  KeyBinding.swift
//  Wurstfinger
//
//  What a single gesture on a key produces.
//

import Foundation

/// What a single gesture on a key produces.
struct KeyBinding: Codable, Equatable {
    /// Displayed text on the key (can differ from output, e.g. "⇧" for shift)
    let label: String

    /// What happens when triggered
    let action: KeyAction

    /// Semantic category — controls behavior like auto-shift, haptics, hint styling.
    /// nil = automatically derived from action (see resolvedCategory).
    let category: KeyCategory?

    /// Optional alternative action for return swipe (swipe out and back)
    let returnAction: KeyAction?

    /// VoiceOver label, only set when different from label (e.g. "Löschen" for "⌫")
    let accessibilityLabel: String?

    /// How the binding is drawn on its key. `nil` derives it: an icon for
    /// actions that have one, otherwise the text label.
    var legend: KeyLegend? = nil

    /// Category: explicit or automatically derived from the action.
    var resolvedCategory: KeyCategory {
        category ?? action.inferredCategory
    }

    /// A copy with a different swipe-return action.
    func with(returnAction: KeyAction?) -> KeyBinding {
        KeyBinding(
            label: label, action: action, category: category,
            returnAction: returnAction, accessibilityLabel: accessibilityLabel, legend: legend
        )
    }

    /// A copy with a different label and legend.
    func with(label: String, legend: KeyLegend?) -> KeyBinding {
        KeyBinding(
            label: label, action: action, category: category,
            returnAction: returnAction, accessibilityLabel: accessibilityLabel, legend: legend
        )
    }
}

/// Explicit appearance of a binding's legend, mirroring Thumb-Key's
/// `KeyDisplay` plus its `MUTED` color variant.
enum KeyLegend: Codable, Equatable {
    /// Not drawn at all (e.g. space-bar cursor swipes).
    case hidden
    /// The text label, drawn in the muted color.
    case muted
    /// An SF Symbol, drawn in the muted color.
    case icon(String)
    /// An SF Symbol that switches to `capsLockIcon` while caps lock is on.
    case capsIcon(String, capsLockIcon: String)
}
