//
//  SpellcheckEngine.swift
//  Wurstfinger
//

import Foundation
import UIKit

struct SpellcheckState: Equatable {
    let word: String?
    let isMisspelled: Bool
    let suggestions: [String]

    static let idle = SpellcheckState(
        word: nil,
        isMisspelled: false,
        suggestions: []
    )
}

protocol WordChecking {
    func isMisspelled(_ word: String, language: String) -> Bool
    func guesses(for word: String, language: String) -> [String]
}

final class AppleWordChecker: WordChecking {
    private let checker = UITextChecker()

    func isMisspelled(_ word: String, language: String) -> Bool {
        let range = NSRange(location: 0, length: word.utf16.count)
        return checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        ).location != NSNotFound
    }

    func guesses(for word: String, language: String) -> [String] {
        let range = NSRange(location: 0, length: word.utf16.count)
        return checker.guesses(
            forWordRange: range,
            in: word,
            language: language
        ) ?? []
    }
}

enum SpellcheckEngine {
    private static let wordCharacters = CharacterSet.letters
        .union(CharacterSet(charactersIn: "-'’"))

    static func currentWord(in context: String?) -> String? {
        guard let context, !context.isEmpty else { return nil }

        let suffix = context.unicodeScalars.reversed().prefix {
            wordCharacters.contains($0)
        }
        var rawCandidate = ""
        for scalar in suffix.reversed() {
            rawCandidate.unicodeScalars.append(scalar)
        }
        let candidate = rawCandidate.trimmingCharacters(
            in: CharacterSet(charactersIn: "-'’")
        )

        guard candidate.count >= 2,
              candidate.unicodeScalars.contains(where: {
                  CharacterSet.letters.contains($0)
              })
        else { return nil }
        return candidate
    }

    static func language(for locale: Locale, available: [String]) -> String? {
        let normalizedIdentifier = normalize(locale.identifier)
        if let exact = available.first(where: { normalize($0) == normalizedIdentifier }) {
            return exact
        }

        guard let languageCode = locale.language.languageCode?.identifier.lowercased()
        else { return nil }
        return available.first {
            normalize($0).split(separator: "-").first == Substring(languageCode)
        }
    }

    static func evaluate(
        context: String?,
        locale: Locale,
        checker: WordChecking,
        availableLanguages: [String] = UITextChecker.availableLanguages
    ) -> SpellcheckState {
        guard let word = currentWord(in: context),
              let language = language(for: locale, available: availableLanguages)
        else { return .idle }

        let misspelled = checker.isMisspelled(word, language: language)
        return SpellcheckState(
            word: word,
            isMisspelled: misspelled,
            suggestions: misspelled
                ? Array(checker.guesses(for: word, language: language).prefix(3))
                : []
        )
    }

    static func matchingCase(
        suggestion: String,
        original: String,
        locale: Locale
    ) -> String {
        if original == original.uppercased(with: locale) {
            return suggestion.uppercased(with: locale)
        }
        if original.first?.isUppercase == true {
            return suggestion.prefix(1).uppercased(with: locale) +
                String(suggestion.dropFirst())
        }
        return suggestion
    }

    private static func normalize(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

extension KeyboardViewModel {
    func scheduleSpellcheckRefresh() {
        guard !spellcheckRefreshPending else { return }
        spellcheckRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            spellcheckRefreshPending = false
            refreshSpellcheck()
        }
    }

    func refreshSpellcheck() {
        guard let target = textInputTarget,
              target.allowsSpellChecking,
              !emojiActive,
              activeModeName == ModeNames.main || activeModeName == ModeNames.shifted
        else {
            spellcheckState = .idle
            return
        }

        spellcheckState = SpellcheckEngine.evaluate(
            context: target.documentContextBeforeInput,
            locale: pipelineLocale ?? Locale.current,
            checker: wordChecker
        )
    }

    func acceptSpellcheckSuggestion(_ suggestion: String) {
        guard let target = textInputTarget,
              target.allowsSpellChecking,
              let original = spellcheckState.word,
              SpellcheckEngine.currentWord(in: target.documentContextBeforeInput) == original
        else { return }

        let replacement = SpellcheckEngine.matchingCase(
            suggestion: suggestion,
            original: original,
            locale: pipelineLocale ?? Locale.current
        )
        for _ in original {
            target.deleteBackward()
        }
        target.insertText(replacement)
        feedbackTap()
        scheduleSpellcheckRefresh()
    }
}
