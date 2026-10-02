//
//  TestHelpers.swift
//  WurstfingerTests
//
//  Shared test helpers for the data-driven pipeline tests.
//  MockTextTarget and makeViewModel are used across multiple test files.
//

import Foundation
import Testing
@testable import WurstfingerApp

/// Mock implementation of TextInputTarget for pipeline tests.
final class MockTextTarget: TextInputTarget {
    enum Event: Equatable {
        case insertText(String)
        case deleteBackward
        case adjustCursor(Int)
    }

    var events: [Event] = []
    var documentContextBeforeInput: String?
    var documentContextAfterInput: String?
    var selectedText: String?
    var hasFullAccess: Bool = false
    var capitalizationMode: TextCapitalizationMode = .sentences
    var fieldKind: TextFieldKind = .text
    var isSecureTextEntry = false
    var documentIdentifier: UUID?

    func insertText(_ text: String) {
        events.append(.insertText(text))
        documentContextBeforeInput = (documentContextBeforeInput ?? "") + text
    }

    func deleteBackward() {
        events.append(.deleteBackward)
        if let ctx = documentContextBeforeInput, !ctx.isEmpty {
            documentContextBeforeInput = String(ctx.dropLast())
        }
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        events.append(.adjustCursor(offset))
    }

    /// Text inserted so far, in order.
    var insertedTexts: [String] {
        events.compactMap {
            if case let .insertText(text) = $0 {
                text
            } else {
                nil
            }
        }
    }
}

/// Records bridge commands instead of posting them.
final class MockTextCommandBridge: TextCommandBridge {
    var isAvailable = true
    var sent: [TextCommand] = []

    func send(_ command: TextCommand) {
        sent.append(command)
    }
}

/// Isolated, in-memory `UserDefaults` for tests.
///
/// Replaces the previous `UserDefaults(suiteName: "test.<UUID>")!` pattern,
/// which created a fresh on-disk suite per call. Under parallel test
/// execution that spammed the prefs directory and could return `nil`,
/// crashing on the force-unwrap. This backing store never touches disk,
/// never returns `nil`, and is fully isolated per instance.
///
/// `KeyboardSettings` reads/writes the injected store only via
/// `object(forKey:)` / `set(_:forKey:)` / `removeObject(forKey:)`; the typed
/// accessors are overridden too as a safety net.
final class InMemoryUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    convenience init() {
        // suiteName nil backs `super` with the standard domain, but every
        // accessor below is overridden so that domain is never consulted.
        self.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        storage[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        storage[defaultName] = nil
    }

    override func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    override func bool(forKey defaultName: String) -> Bool {
        (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false
    }

    override func integer(forKey defaultName: String) -> Int {
        (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0
    }

    override func double(forKey defaultName: String) -> Double {
        (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0
    }

    override func float(forKey defaultName: String) -> Float {
        (object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0
    }
}

/// Creates a KeyboardViewModel wired to a MockTextTarget for testing.
///
/// Main-actor only, like the keyboard: the view model schedules spell-check
/// refreshes on the main queue, which must not run concurrently with a test.
///
/// Auto-capitalization is off unless requested, so typing sequences stay
/// predictable; `settings` pre-populates other defaults.
@MainActor
func makeViewModel(
    languageId: String = "de_DE",
    autoCapitalize: Bool = false,
    settings: [SettingsKey: Any] = [:],
    advanceToNextInputMode: @escaping () -> Void = {},
    dismissKeyboard: @escaping () -> Void = {}
) -> (KeyboardViewModel, MockTextTarget) {
    let defaults = InMemoryUserDefaults()
    defaults.set(autoCapitalize, forKey: SettingsKey.autoCapitalizeEnabled.rawValue)
    for (key, value) in settings {
        defaults.set(value, forKey: key.rawValue)
    }
    let vm = KeyboardViewModel(userDefaults: defaults, shouldPersistSettings: false)
    let target = MockTextTarget()
    vm.bindTextInputTarget(target)
    vm.bindViewControllerActions(
        advanceToNextInputMode: advanceToNextInputMode,
        dismissKeyboard: dismissKeyboard
    )
    vm.loadDefinition(for: languageId)
    return (vm, target)
}
