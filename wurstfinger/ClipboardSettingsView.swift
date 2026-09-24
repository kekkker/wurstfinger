//
//  ClipboardSettingsView.swift
//  wurstfinger
//
//  Thumb-Key's clipboard history settings.
//

import SwiftUI

struct ClipboardSettingsView: View {
    @AppStorage(SettingsKey.clipboardHistoryEnabled.rawValue, store: SharedDefaults.store)
    private var historyEnabled = ClipboardSettings().historyEnabled

    @AppStorage(SettingsKey.clipboardAutoCleanup.rawValue, store: SharedDefaults.store)
    private var autoCleanupEnabled = ClipboardSettings().autoCleanupEnabled

    @AppStorage(SettingsKey.clipboardCleanupMinutes.rawValue, store: SharedDefaults.store)
    private var cleanupAfterMinutes = ClipboardSettings().cleanupAfterMinutes

    @AppStorage(SettingsKey.clipboardSizeLimit.rawValue, store: SharedDefaults.store)
    private var sizeLimitEnabled = ClipboardSettings().sizeLimitEnabled

    @AppStorage(SettingsKey.clipboardMaxItems.rawValue, store: SharedDefaults.store)
    private var maxItems = ClipboardSettings().maxItems

    @AppStorage(SettingsKey.clipboardPrivate.rawValue, store: SharedDefaults.store)
    private var usesPrivateClipboard = ClipboardSettings().usesPrivateClipboard

    var body: some View {
        Form {
            Section {
                Toggle("Clipboard history", isOn: $historyEnabled)
            } footer: {
                Text("Keeps what you copy. Swipe down and back on the 123 key to open it. Needs Full Access.")
            }

            Section {
                Toggle("Clean up automatically", isOn: $autoCleanupEnabled)
                if autoCleanupEnabled {
                    Picker("Remove after", selection: $cleanupAfterMinutes) {
                        ForEach(ClipboardSettings.cleanupChoices, id: \.self) { minutes in
                            Text(Self.durationLabel(minutes)).tag(minutes)
                        }
                    }
                }
                Toggle("Limit size", isOn: $sizeLimitEnabled)
                if sizeLimitEnabled {
                    Stepper(value: $maxItems, in: ClipboardSettings.maxItemsRange) {
                        HStack {
                            Text("Maximum items")
                            Spacer()
                            Text("\(maxItems)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Toggle(isOn: $usesPrivateClipboard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private clipboard")
                        Text("Copies stay in the keyboard's history instead of the system clipboard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Pinned items are never removed automatically.")
            }
            .disabled(!historyEnabled)
        }
        .navigationTitle("Clipboard")
    }

    static func durationLabel(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = minutes < 60 ? [.minute] : (minutes < 1440 ? [.hour] : [.day])
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)"
    }
}

#Preview {
    NavigationStack {
        ClipboardSettingsView()
    }
}
