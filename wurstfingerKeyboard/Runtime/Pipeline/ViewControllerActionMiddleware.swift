//
//  ViewControllerActionMiddleware.swift
//  Wurstfinger
//
//  Handles actions that require UIInputViewController methods:
//  advanceToNextInputMode and dismissKeyboard.
//

import Foundation

/// Handles view-controller-specific actions (`advanceToNextInputMode`,
/// `dismissKeyboard`, `openSettings`) by delegating to injected closures.
///
/// The closures are captured weakly over the controller at pipeline
/// construction time, keeping the middleware free of UIKit dependencies.
struct ViewControllerActionMiddleware: ActionMiddleware {
    let onAdvanceToNextInputMode: () -> Void
    let onDismissKeyboard: () -> Void
    var onOpenSettings: () -> Void = {}

    func process(_ context: ActionContext, next: (ActionContext) -> Void) {
        switch context.action {
        case .advanceToNextInputMode:
            onAdvanceToNextInputMode()
        case .dismissKeyboard:
            onDismissKeyboard()
        case .openSettings:
            onOpenSettings()
        default:
            break
        }
        next(context)
    }
}
