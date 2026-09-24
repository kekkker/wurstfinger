//
//  RecentEmoji.swift
//  Wurstfinger
//
//  Most recently used emoji, shown first in the emoji panel.
//

import Foundation

enum RecentEmoji {
    static let limit = 30

    static func load(from defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: SettingsKey.recentEmoji.rawValue) ?? []
    }

    /// Moves `emoji` to the front of the recent list.
    static func record(_ emoji: String, in defaults: UserDefaults) {
        var recent = load(from: defaults).filter { $0 != emoji }
        recent.insert(emoji, at: 0)
        defaults.set(Array(recent.prefix(limit)), forKey: SettingsKey.recentEmoji.rawValue)
    }
}
