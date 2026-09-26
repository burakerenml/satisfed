//
//  EnergyCheck.swift
//  Shiphaton App
//
//  A one-tap energy check-in. Four moods, no numbers, no scores —
//  just enough signal to answer with, and to change your mind on.
//

import Foundation
import SwiftData

enum EnergyLevel: String, Codable, CaseIterable, Identifiable {
    case low
    case meh
    case steady
    case high

    var id: String { rawValue }

    /// All four are faces on purpose. A lightning bolt among three faces
    /// read as a different icon set entirely, and the row is one question
    /// with four answers, not three moods plus a symbol.
    var emoji: String {
        switch self {
        case .low: "🫠"
        case .meh: "😑"
        case .steady: "😌"
        case .high: "🤩"
        }
    }

    var label: String {
        switch self {
        case .low: "Drained"
        case .meh: "Meh"
        case .steady: "Steady"
        case .high: "Energized"
        }
    }

    /// First line of the acknowledgment: what you told the app, said back
    /// warmly. Never a verdict, never advice.
    var headline: String {
        switch self {
        case .low: "Running low today"
        case .meh: "Somewhere in the middle"
        case .steady: "Feeling steady"
        case .high: "Buzzing today"
        }
    }

    /// Second line: one gentle, additive follow-up. Something food can add,
    /// never something to cut or fix.
    var response: String {
        switch self {
        case .low: "A bite with staying power can lift it."
        case .meh: "Something you actually want might shift it."
        case .steady: "A good bite can keep it right here."
        case .high: "Ride it. Food can keep it going."
        }
    }
}

/// Loose time-of-day buckets. The app's unit for "when": no clock
/// precision, no numbers, just the shape of a day.
enum Daypart: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case late

    init(from date: Date) {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: self = .morning
        case 11..<16: self = .afternoon
        case 16..<22: self = .evening
        default: self = .late
        }
    }

    var id: String { rawValue }

    static var current: Daypart { Daypart(from: .now) }

    var label: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .late: "Late night"
        }
    }

    var emoji: String {
        switch self {
        case .morning: "☀️"
        case .afternoon: "🌤️"
        case .evening: "🌙"
        case .late: "✨"
        }
    }
}

@Model
final class EnergyCheck {
    var date: Date
    var levelRaw: String

    init(date: Date = .now, level: EnergyLevel) {
        self.date = date
        self.levelRaw = level.rawValue
    }

    var level: EnergyLevel {
        get { EnergyLevel(rawValue: levelRaw) ?? .steady }
        set { levelRaw = newValue.rawValue }
    }
}
