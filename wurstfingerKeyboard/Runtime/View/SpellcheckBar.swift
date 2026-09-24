//
//  SpellcheckBar.swift
//  Wurstfinger
//

import SwiftUI

struct SpellcheckBar: View {
    let state: SpellcheckState
    let onSuggestion: (String) -> Void
    var palette = KeyboardPalette.system

    var body: some View {
        HStack(spacing: 8) {
            if let word = state.word {
                Image(systemName: state.isMisspelled
                    ? "exclamationmark.circle.fill"
                    : "checkmark.circle.fill")
                    .foregroundStyle(state.isMisspelled ? Color.red : Color.green)

                Text(word)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.isMisspelled ? Color.red : palette.secondary)
                    .lineLimit(1)

                if state.isMisspelled {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(state.suggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    onSuggestion(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spellcheckBar")
    }
}
