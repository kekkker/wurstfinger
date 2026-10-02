//
//  KeyboardRegistry.swift
//  Wurstfinger
//
//  Registry for keyboard layouts with lazy loading and caching.
//

import Foundation

/// Thread-safe cache of loaded keyboard definitions.
final class DefinitionCache {
    private let definitionsByID: [String: KeyboardDefinition]
    private var cache: [String: KeyboardDefinition] = [:]
    private let lock = NSLock()

    init(definitions: [KeyboardDefinition]) {
        definitionsByID = definitions.reduce(into: [:]) { dict, def in
            dict[def.id] = def
        }
    }

    /// Loads the full definition for a keyboard ID, caching the result.
    func load(id: String) -> KeyboardDefinition? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[id] {
            return cached
        }
        guard let definition = definitionsByID[id] else {
            return nil
        }
        cache[id] = definition
        return definition
    }

    /// Removes a cached definition (e.g. on memory warning).
    func evict(id: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: id)
    }

    /// Clears the entire cache.
    func evictAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    /// Whether a definition is currently cached.
    func isCached(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[id] != nil
    }
}

/// Registry for keyboard layouts.
/// Exposes lightweight metadata via `available` and loads full definitions on demand.
enum KeyboardRegistry {
    /// All available keyboard layouts (lightweight metadata only).
    static let available: [KeyboardInfo] = LanguageDefinitions.all.map { KeyboardInfo(from: $0) }

    /// The process-wide definition cache.
    private static let shared = DefinitionCache(definitions: LanguageDefinitions.all)

    /// Loads the full definition for a keyboard ID, caching the result.
    static func load(id: String) -> KeyboardDefinition? {
        shared.load(id: id)
    }
}
