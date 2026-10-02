//
//  ModifyKeysSettingsView.swift
//  wurstfinger
//
//  Thumb-Key's "Modify keys": change individual keys with YAML.
//

import SwiftUI

struct ModifyKeysSettingsView: View {
    @AppStorage(SettingsKey.keyModifications.rawValue, store: SharedDefaults.store)
    private var keyModifications = ""

    private static let example = """
    ENThumbKey:
      main:
        key1_0:
          center: { text: ñ }
        key0_3:
          center: { keyAction: SwitchLanguage }
          left: { keyAction: ToggleEmojiMode }
    """

    var body: some View {
        Form {
            Section {
                TextEditor(text: $keyModifications)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 260)
            } header: {
                Text("YAML")
            } footer: {
                validation
            }

            Section {
                Text(Self.example)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button("Use example") {
                    keyModifications = Self.example
                }
            } header: {
                Text("Example")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Same format as Thumb-Key: layout, mode (main, shifted or numeric), key{row}_{column}, then a direction.")
                    Text("Directions are center, left, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft and longPress.")
                    Text("Each takes text, displayText, keyAction, swipeReturnText, swipeReturnAction or remove.")
                    Text("Layouts are ENThumbKey, RUThumbKey or a Wurstfinger layout id such as de_DE.")
                }
            }
        }
        .navigationTitle("Modify keys")
    }

    @ViewBuilder
    private var validation: some View {
        if keyModifications.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No changes.")
        } else if let error = validationError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        } else {
            Label("Applied the next time the keyboard opens.", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }

    private var validationError: String? {
        do {
            try KeyModifications.validate(keyModifications)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

#Preview {
    NavigationStack {
        ModifyKeysSettingsView()
    }
}
