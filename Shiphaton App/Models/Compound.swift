//
//  Compound.swift
//  Shiphaton App
//
//  The three satisfaction builders: protein, fibre, healthy fats.
//  Presence only — never amounts, never numbers.
//

import SwiftUI

enum Compound: String, Codable, CaseIterable, Identifiable {
    case protein
    case fibre
    case fats

    var id: String { rawValue }

    var label: String {
        switch self {
        case .protein: "Protein"
        case .fibre: "Fibre"
        case .fats: "Healthy Fats"
        }
    }

    var shortLabel: String {
        switch self {
        case .protein: "Protein"
        case .fibre: "Fibre"
        case .fats: "Fats"
        }
    }

    var emoji: String {
        switch self {
        case .protein: "🍳"
        case .fibre: "🌾"
        case .fats: "🥑"
        }
    }

    var color: Color {
        switch self {
        case .protein: Palette.protein
        case .fibre: Palette.fibre
        case .fats: Palette.honey
        }
    }

    var tint: Color {
        switch self {
        case .protein: Palette.proteinTint
        case .fibre: Palette.fibreTint
        case .fats: Palette.honeyTint
        }
    }

    /// Gentle one-liner about why this builder helps.
    var whisper: String {
        switch self {
        case .protein: "keeps you satisfied the longest"
        case .fibre: "slows things down, steadies energy"
        case .fats: "makes it feel like a real treat"
        }
    }

    /// The AI bots speak of this builder as "protein" / "fibre" /
    /// "healthy_fats". The server folds stray spellings onto those, but a
    /// model that says "fat" or "fiber" still lands here safely.
    init?(aiValue: String) {
        switch aiValue.trimmingCharacters(in: .whitespaces).lowercased() {
        case "protein", "proteins": self = .protein
        case "fibre", "fiber": self = .fibre
        case "healthy_fats", "healthy_fat", "healthy fats", "healthy fat", "fats", "fat": self = .fats
        default: return nil
        }
    }

    var aiValue: String {
        switch self {
        case .protein: "protein"
        case .fibre: "fibre"
        case .fats: "healthy_fats"
        }
    }
}

/// Why this meal is happening — context, never judgment.
enum MealContext: String, Codable, CaseIterable, Identifiable {
    case craving
    case out
    case family
    case pantry
    case hungry

    var id: String { rawValue }

    var label: String {
        switch self {
        case .craving: "Craving it"
        case .out: "Eating out"
        case .family: "Family food"
        case .pantry: "Recipe maker"
        case .hungry: "Just hungry"
        }
    }

    var emoji: String {
        switch self {
        case .craving: "✨"
        case .out: "🥡"
        case .family: "🏡"
        case .pantry: "🧺"
        case .hungry: "⚡️"
        }
    }
}
