//
//  CravingHistory.swift
//  Shiphaton App
//
//  What the craving translator knows about you: the cravings you've
//  picked lately (kept on this device), and the recent meals and energy
//  check-ins already logged, shaped into the small history the AI mines
//  for patterns. Words for "when", never clock times or counts.
//

import Foundation

enum CravingLog {

    struct Entry: Codable {
        let date: Date
        let craving: String
    }

    private static let key = "cravingLog.v1"
    private static let cap = 40

    /// Remembers a pick. Tapping the same chip twice in a row within the
    /// hour is one craving, not two.
    static func record(_ craving: String, at date: Date = .now) {
        var stored = entries()
        if let last = stored.first, last.craving == craving, date.timeIntervalSince(last.date) < 3600 { return }
        stored.insert(Entry(date: date, craving: craving), at: 0)
        if stored.count > cap { stored = Array(stored.prefix(cap)) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func recent(days: Int = 7, now: Date = .now) -> [Entry] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return entries().filter { $0.date >= cutoff }
    }

    private static func entries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded
    }
}

enum RecentData {

    /// The last week, as the translator prompt expects it: recent meals
    /// and which builders they covered, past cravings, and moods. `nil`
    /// when there's nothing logged yet, so no empty block gets sent.
    static func payload(meals: [Meal], energyChecks: [EnergyCheck], now: Date = .now) -> [String: Any]? {
        let cutoff = now.addingTimeInterval(-7 * 86_400)

        let recentMeals: [[String: Any]] = meals
            .filter { $0.date >= cutoff }
            .prefix(20)
            .map { meal in
                [
                    "when": when(meal.date, now: now),
                    "items": ([meal.name] + meal.boosts).joined(separator: " + "),
                    "compounds_covered": meal.compounds.map(\.aiValue).sorted(),
                ]
            }

        let recentCravings: [[String: Any]] = CravingLog.recent(now: now)
            .prefix(10)
            .map { ["when": when($0.date, now: now), "craving": $0.craving] }

        let moods: [[String: Any]] = energyChecks
            .filter { $0.date >= cutoff }
            .prefix(10)
            .map { ["when": when($0.date, now: now), "mood": $0.level.label] }

        guard !recentMeals.isEmpty || !recentCravings.isEmpty || !moods.isEmpty else { return nil }
        return [
            "recent_meals": recentMeals,
            "recent_cravings": recentCravings,
            "moods": moods,
        ]
    }

    /// "today afternoon", "yesterday evening", "Monday morning".
    static func when(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            day = "yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            day = formatter.string(from: date)
        }
        return "\(day) \(Daypart(from: date).label.lowercased())"
    }
}
