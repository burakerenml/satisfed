//
//  CustomIngredientStore.swift
//  Shiphaton App
//
//  Ingredients someone typed in that the recipe maker's small library
//  doesn't know yet. They live in UserDefaults on this device, so the
//  next visit finds them sitting in the grid with everything else.
//

import Foundation

enum CustomIngredientStore {

    private static let key = "customIngredients.v1"

    /// The stored shape. Only a name and an emoji: which builders an
    /// ingredient brings is knowledge we don't have for these, so they
    /// come in empty-handed and simply ride along to the chef.
    private struct Entry: Codable {
        let id: String
        let name: String
        let emoji: String
    }

    /// Everything added on this device, newest first.
    static func all() -> [Ingredient] {
        entries().map { Ingredient($0.id, $0.name, $0.emoji, adds: []) }
    }

    /// Keeps a typed ingredient for next time. A name that's already here
    /// wins, so tapping add twice never doubles up the grid.
    @discardableResult
    static func add(name: String, emoji: String) -> Ingredient {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var stored = entries()
        if let existing = stored.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return Ingredient(existing.id, existing.name, existing.emoji, adds: [])
        }
        let entry = Entry(id: "customIngredient.\(UUID().uuidString)", name: trimmed, emoji: emoji)
        stored.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return Ingredient(entry.id, entry.name, entry.emoji, adds: [])
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
