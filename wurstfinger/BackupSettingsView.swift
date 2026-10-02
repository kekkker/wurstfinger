//
//  BackupSettingsView.swift
//  wurstfinger
//
//  Thumb-Key's backup and restore: export all keyboard settings to a file,
//  import them again, or reset everything to the defaults.
//

import SwiftUI
import UniformTypeIdentifiers

/// All keyboard settings as a property list file.
struct SettingsBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.propertyList]

    var values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        self.values = values
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        return FileWrapper(regularFileWithContents: data)
    }

    /// Current settings from the shared store.
    static func current(from defaults: UserDefaults = SharedDefaults.store) -> SettingsBackupDocument {
        var values: [String: Any] = [:]
        for key in SettingsKey.allCases where key.isBackedUp {
            if let value = defaults.object(forKey: key.rawValue) {
                values[key.rawValue] = value
            }
        }
        return SettingsBackupDocument(values: values)
    }

    /// Replaces the stored settings with this backup's.
    func restore(into defaults: UserDefaults = SharedDefaults.store) {
        for key in SettingsKey.allCases where key.isBackedUp {
            defaults.set(values[key.rawValue], forKey: key.rawValue)
        }
    }
}

extension SettingsKey {
    /// Device-specific state that a backup must not carry over.
    var isBackedUp: Bool {
        self != .keyboardFullAccess
    }
}

struct BackupSettingsView: View {
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmingReset = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Button("Back up settings") {
                    exporting = true
                }
                Button("Restore settings") {
                    importing = true
                }
            } footer: {
                Text("Saves or loads every keyboard setting, including clipboard history, as a file.")
            }

            Section {
                Button("Reset to defaults", role: .destructive) {
                    confirmingReset = true
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Backup and restore")
        .fileExporter(
            isPresented: $exporting,
            document: SettingsBackupDocument.current(),
            contentType: .propertyList,
            defaultFilename: "\(Self.dateStamp())-wurstfinger"
        ) { result in
            if case .success = result {
                message = String(localized: "Settings saved.")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList]) { result in
            restore(from: result)
        }
        .confirmationDialog(
            "Reset all settings to their defaults?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                for key in SettingsKey.allCases where key.isBackedUp {
                    SharedDefaults.store.removeObject(forKey: key.rawValue)
                }
                message = String(localized: "Settings reset.")
            }
        }
    }

    private func restore(from result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            message = String(localized: "That file is not a Wurstfinger backup.")
            return
        }
        SettingsBackupDocument(values: values).restore()
        message = String(localized: "Settings restored.")
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

#Preview {
    NavigationStack {
        BackupSettingsView()
    }
}
