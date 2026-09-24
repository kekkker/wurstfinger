//
//  AutoCapitalizationMiddleware.swift
//  Wurstfinger
//
//  Re-evaluates the shift state after text is committed.
//

import Foundation

/// Runs after the text-mutating middlewares and settles the shift state the
/// way Thumb-Key does after every committed text: language auto-capitalizers
/// run first (e.g. " i " → " I "), then the keyboard shifts when the next
/// character should be uppercase and unshifts otherwise. That unshift is
/// what makes a manual shift apply to one character only.
///
/// The decisions are injected as closures so this file stays independent of
/// the view model and the document proxy.
struct AutoCapitalizationMiddleware: ActionMiddleware {
    /// Whether auto-capitalization is enabled at all.
    let isEnabled: () -> Bool

    /// Applies the language's text rules before the check.
    let applyAutoCapitalizers: () -> Void

    /// Whether the next character should be uppercase.
    let shouldCapitalize: () -> Bool

    /// Shifts (`true`) or unshifts (`false`). The owner ignores this on the
    /// numeric layer and keeps caps lock.
    let setShifted: (Bool) -> Void

    func process(_ context: ActionContext, next: (ActionContext) -> Void) {
        next(context)
        guard Self.affectsCapitalization(context.action) else { return }
        guard isEnabled() else {
            setShifted(false)
            return
        }
        applyAutoCapitalizers()
        setShifted(shouldCapitalize())
    }

    /// Actions that commit text. Kept static so tests can verify the policy
    /// without constructing a middleware instance.
    static func affectsCapitalization(_ action: KeyAction) -> Bool {
        switch action {
        case .commitText, .replaceLastText, .space, .newline, .compose, .cycleAccents:
            true
        default:
            false
        }
    }
}
