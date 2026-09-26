//
//  Meal.swift
//  Shiphaton App
//
//  A logged meal or snack. Stores what it was, the context, which
//  satisfaction builders it covered, and any boosts the user added.
//

import Foundation
import SwiftData

@Model
final class Meal {
    var name: String
    var emoji: String
    var date: Date
    var contextRaw: String?
    /// Raw values of the compounds present in the final meal.
    var compoundsRaw: [String]
    /// Names of boosts the user chose to add (e.g. "Greek yogurt dip").
    var boosts: [String]
    /// How to make it, one line per step, in order. Only the chef's ideas
    /// come with these; a snapped plate or a tapped pantry combo has none,
    /// and an empty list simply shows no steps. Defaulted so an existing
    /// store migrates without a word.
    var steps: [String] = []
    @Attribute(.externalStorage) var photoData: Data?

    init(
        name: String,
        emoji: String,
        date: Date = .now,
        context: MealContext? = nil,
        compounds: Set<Compound> = [],
        boosts: [String] = [],
        steps: [String] = [],
        photoData: Data? = nil
    ) {
        self.name = name
        self.emoji = emoji
        self.date = date
        self.contextRaw = context?.rawValue
        self.compoundsRaw = compounds.map(\.rawValue)
        self.boosts = boosts
        self.steps = steps
        self.photoData = photoData
    }

    var compounds: Set<Compound> {
        get { Set(compoundsRaw.compactMap(Compound.init(rawValue:))) }
        set { compoundsRaw = newValue.map(\.rawValue) }
    }

    var context: MealContext? {
        get { contextRaw.flatMap(MealContext.init(rawValue:)) }
        set { contextRaw = newValue?.rawValue }
    }

    var isComplete: Bool { compounds.count == Compound.allCases.count }
}
