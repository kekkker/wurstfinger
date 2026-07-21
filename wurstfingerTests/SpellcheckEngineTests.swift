//
//  SpellcheckEngineTests.swift
//  wurstfingerTests
//

import Foundation
import Testing
@testable import WurstfingerApp

private struct FakeWordChecker: WordChecking {
    let misspellings: [String: [String]]

    func isMisspelled(_ word: String, language _: String) -> Bool {
        misspellings[word] != nil
    }

    func guesses(for word: String, language _: String) -> [String] {
        misspellings[word] ?? []
    }
}

struct SpellcheckEngineTests {
    @Test func extractsCurrentWordAfterPunctuation() {
        #expect(SpellcheckEngine.currentWord(in: "Well, teh") == "teh")
        #expect(SpellcheckEngine.currentWord(in: "don't") == "don't")
        #expect(SpellcheckEngine.currentWord(in: "done ") == nil)
    }

    @Test func reportsMisspellingAndLimitsGuesses() {
        let checker = FakeWordChecker(misspellings: [
            "teh": ["the", "ten", "tech", "tea"],
        ])
        let result = SpellcheckEngine.evaluate(
            context: "teh",
            locale: Locale(identifier: "en_US"),
            checker: checker,
            availableLanguages: ["en_US"]
        )

        #expect(result.word == "teh")
        #expect(result.isMisspelled)
        #expect(result.suggestions == ["the", "ten", "tech"])
    }

    @Test func preservesCapitalizationWhenReplacing() {
        let locale = Locale(identifier: "en_US")
        #expect(SpellcheckEngine.matchingCase(
            suggestion: "the", original: "Teh", locale: locale
        ) == "The")
        #expect(SpellcheckEngine.matchingCase(
            suggestion: "the", original: "TEH", locale: locale
        ) == "THE")
    }
}
