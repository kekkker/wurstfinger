//
//  KeyboardRegistryTests.swift
//  WurstfingerTests
//
//  Tests for KeyboardInfo and KeyboardRegistry.
//

import Foundation
import Testing
@testable import WurstfingerApp

// MARK: - KeyboardInfo

struct KeyboardInfoTests {
    @Test func initFromDefinition() {
        let definition = LanguageDefinitions.german
        let info = KeyboardInfo(from: definition)
        #expect(info.id == definition.id)
        #expect(info.title == definition.title)
        #expect(info.localeIdentifier == definition.localeIdentifier)
    }

    @Test func identifiable() {
        let info = KeyboardInfo(id: "test", title: "Test", localeIdentifier: "en_US")
        #expect(info.id == "test")
    }
}

// MARK: - KeyboardRegistry

@Suite(.serialized)
struct KeyboardRegistryTests {
    @Test func availableContainsAllLanguages() {
        let expectedIDs = Set(LanguageDefinitions.all.map(\.id))
        let actualIDs = Set(KeyboardRegistry.available.map(\.id))
        #expect(actualIDs == expectedIDs)
    }

    @Test func availableContainsGerman() {
        let german = KeyboardRegistry.available.first { $0.id == LanguageDefinitions.german.id }
        #expect(german != nil)
        #expect(german?.title == LanguageDefinitions.german.title)
        #expect(german?.localeIdentifier == LanguageDefinitions.german.localeIdentifier)
    }

    @Test func loadReturnsCorrectDefinition() {
        let definition = KeyboardRegistry.load(id: LanguageDefinitions.german.id)
        #expect(definition != nil)
        #expect(definition?.id == LanguageDefinitions.german.id)
        #expect(definition?.title == LanguageDefinitions.german.title)
    }

    @Test func loadNonexistentReturnsNil() {
        #expect(KeyboardRegistry.load(id: "nonexistent_layout") == nil)
    }
}

/// Uses its own cache, since the registry's is shared by every test running in parallel.
struct DefinitionCacheTests {
    private let cache = DefinitionCache(definitions: [LanguageDefinitions.german, LanguageDefinitions.english])

    @Test func loadCachesResult() {
        #expect(!cache.isCached(id: LanguageDefinitions.german.id))
        let first = cache.load(id: LanguageDefinitions.german.id)
        #expect(first != nil)
        #expect(cache.isCached(id: LanguageDefinitions.german.id))
        let second = cache.load(id: LanguageDefinitions.german.id)
        #expect(first == second)
    }

    @Test func unknownIdIsNotCached() {
        #expect(cache.load(id: "nonexistent_layout") == nil)
        #expect(!cache.isCached(id: "nonexistent_layout"))
    }

    @Test func evictRemovesFromCache() {
        _ = cache.load(id: LanguageDefinitions.german.id)
        #expect(cache.isCached(id: LanguageDefinitions.german.id))
        cache.evict(id: LanguageDefinitions.german.id)
        #expect(!cache.isCached(id: LanguageDefinitions.german.id))
        // After evict, load should still work (rebuilds from the definitions)
        #expect(cache.load(id: LanguageDefinitions.german.id) != nil)
    }

    @Test func evictAllClearsCache() {
        _ = cache.load(id: LanguageDefinitions.german.id)
        _ = cache.load(id: LanguageDefinitions.english.id)
        #expect(cache.isCached(id: LanguageDefinitions.german.id))
        #expect(cache.isCached(id: LanguageDefinitions.english.id))
        cache.evictAll()
        #expect(!cache.isCached(id: LanguageDefinitions.german.id))
        #expect(!cache.isCached(id: LanguageDefinitions.english.id))
    }

    @Test func concurrentLoadsAreSafe() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 200 {
                group.addTask {
                    if index.isMultiple(of: 10) {
                        cache.evictAll()
                    }
                    _ = cache.load(id: index.isMultiple(of: 2) ? LanguageDefinitions.german.id : LanguageDefinitions.english.id)
                }
            }
        }
        #expect(cache.load(id: LanguageDefinitions.english.id) != nil)
    }
}
