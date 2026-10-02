//
//  ClipboardHistory.swift
//  Wurstfinger
//
//  Thumb-Key's clipboard history: recent copies with pinning, automatic
//  cleanup and a size limit, plus the optional private clipboard that keeps
//  copies out of the system pasteboard.
//

import Combine
import Foundation
import UIKit

/// One remembered clipboard entry.
struct ClipboardItem: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    var date: Date
    var pinned: Bool
}

/// Clipboard history settings (Thumb-Key defaults).
struct ClipboardSettings: Equatable {
    var historyEnabled = false
    var autoCleanupEnabled = true
    var cleanupAfterMinutes = 120
    var sizeLimitEnabled = true
    var maxItems = 20
    var usesPrivateClipboard = false

    static let cleanupChoices = [5, 10, 30, 60, 120, 240, 720, 1440, 2880, 5760, 10080]
    static let maxItemsRange = 2 ... 100

    static func load(from defaults: UserDefaults) -> ClipboardSettings {
        var settings = ClipboardSettings()
        settings.historyEnabled = defaults.object(forKey: SettingsKey.clipboardHistoryEnabled.rawValue) as? Bool
            ?? settings.historyEnabled
        settings.autoCleanupEnabled = defaults.object(forKey: SettingsKey.clipboardAutoCleanup.rawValue) as? Bool
            ?? settings.autoCleanupEnabled
        settings.cleanupAfterMinutes = defaults.object(forKey: SettingsKey.clipboardCleanupMinutes.rawValue) as? Int
            ?? settings.cleanupAfterMinutes
        settings.sizeLimitEnabled = defaults.object(forKey: SettingsKey.clipboardSizeLimit.rawValue) as? Bool
            ?? settings.sizeLimitEnabled
        settings.maxItems = defaults.object(forKey: SettingsKey.clipboardMaxItems.rawValue) as? Int
            ?? settings.maxItems
        settings.usesPrivateClipboard = defaults.object(forKey: SettingsKey.clipboardPrivate.rawValue) as? Bool
            ?? settings.usesPrivateClipboard
        return settings
    }
}

/// Copies and pastes for the keyboard, honoring the clipboard settings.
protocol ClipboardService: AnyObject {
    func copy(_ text: String)
    /// Text a paste should insert, if any.
    func textToPaste() -> String?
}

/// Persistent clipboard history shared between the keyboard and the app.
final class ClipboardHistory: ObservableObject, ClipboardService {
    @Published private(set) var items: [ClipboardItem] = []

    private let defaults: UserDefaults
    private let now: () -> Date
    private let hasFullAccess: () -> Bool
    private var lastPasteboardChangeCount: Int?

    init(
        defaults: UserDefaults = SharedDefaults.store,
        now: @escaping () -> Date = Date.init,
        hasFullAccess: @escaping () -> Bool = { true }
    ) {
        self.defaults = defaults
        self.now = now
        self.hasFullAccess = hasFullAccess
        items = Self.load(from: defaults)
    }

    var settings: ClipboardSettings {
        ClipboardSettings.load(from: defaults)
    }

    /// Pinned first, then newest first.
    var sortedItems: [ClipboardItem] {
        items.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned
            }
            return lhs.date > rhs.date
        }
    }

    // MARK: - ClipboardService

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let settings = settings
        if settings.historyEnabled {
            add(text)
        }
        if !(settings.historyEnabled && settings.usesPrivateClipboard), hasFullAccess() {
            UIPasteboard.general.string = text
            lastPasteboardChangeCount = UIPasteboard.general.changeCount
        }
    }

    func textToPaste() -> String? {
        let settings = settings
        if settings.historyEnabled, settings.usesPrivateClipboard {
            return items.max { $0.date < $1.date }?.text
        }
        guard hasFullAccess() else { return nil }
        return UIPasteboard.general.string
    }

    // MARK: - History

    /// Records `text`. A duplicate only moves to the top.
    func add(_ text: String) {
        guard settings.historyEnabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        reload()
        if let index = items.firstIndex(where: { $0.text == text }) {
            items[index].date = now()
        } else {
            items.append(ClipboardItem(id: UUID(), text: text, date: now(), pinned: false))
        }
        applyLimits()
        save()
    }

    /// Picks up text copied elsewhere since the last check.
    func captureSystemPasteboard() {
        guard settings.historyEnabled, hasFullAccess() else { return }
        let changeCount = UIPasteboard.general.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount
        guard UIPasteboard.general.hasStrings, let text = UIPasteboard.general.string else { return }
        add(text)
    }

    func delete(_ item: ClipboardItem) {
        reload()
        items.removeAll { $0.id == item.id }
        save()
    }

    func togglePin(_ item: ClipboardItem) {
        reload()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        save()
    }

    /// Removes everything except pinned items.
    func clearUnpinned() {
        reload()
        items.removeAll { !$0.pinned }
        save()
    }

    /// Drops expired items, or everything when history is off.
    func purge() {
        reload()
        if settings.historyEnabled {
            applyLimits()
        } else {
            items.removeAll()
        }
        save()
    }

    func reload() {
        let stored = Self.load(from: defaults)
        if stored != items {
            items = stored
        }
    }

    // MARK: - Private

    private func applyLimits() {
        let settings = settings
        if settings.autoCleanupEnabled {
            let cutoff = now().addingTimeInterval(-Double(settings.cleanupAfterMinutes) * 60)
            items.removeAll { !$0.pinned && $0.date < cutoff }
        }
        if settings.sizeLimitEnabled {
            let unpinned = items.filter { !$0.pinned }.sorted { $0.date > $1.date }
            let overflow = unpinned.dropFirst(settings.maxItems).map(\.id)
            items.removeAll { overflow.contains($0.id) }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: SettingsKey.clipboardItems.rawValue)
    }

    private static func load(from defaults: UserDefaults) -> [ClipboardItem] {
        guard let data = defaults.data(forKey: SettingsKey.clipboardItems.rawValue),
              let items = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return [] }
        return items
    }
}
