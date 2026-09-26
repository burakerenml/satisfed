//
//  CustomFoodStore.swift
//  Shiphaton App
//
//  Meals someone typed in that our small on-device library doesn't know
//  yet. They live in UserDefaults on this device, so the very next log
//  finds them the moment the first letters land in the search field.
//

import Foundation

enum CustomFoodStore {

    private static let key = "customFoods.v1"

    /// The stored shape. Only a name and an emoji: what a builder-level
    /// food already brings is knowledge we don't have for these, so the
    /// build step falls back to the generic boosts.
    private struct Entry: Codable {
        let id: String
        let name: String
        let emoji: String
    }

    /// Everything added on this device, newest first.
    static func all() -> [Food] {
        entries().map { Food($0.id, $0.name, $0.emoji, has: []) }
    }

    /// Keeps a typed meal for next time. A name that's already here wins,
    /// so tapping add twice never doubles up the grid.
    @discardableResult
    static func add(name: String, emoji: String) -> Food {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var stored = entries()
        if let existing = stored.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return Food(existing.id, existing.name, existing.emoji, has: [])
        }
        let entry = Entry(id: "custom.\(UUID().uuidString)", name: trimmed, emoji: emoji)
        stored.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return Food(entry.id, entry.name, entry.emoji, has: [])
    }

    static func remove(id: String) {
        let stored = entries().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func entries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded
    }
}
