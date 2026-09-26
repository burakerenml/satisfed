//
//  Profile.swift
//  Shiphaton App
//
//  What onboarding gathers about the person, and the couple of app
//  preferences the You tab still needs. Everything lives in UserDefaults
//  under `ProfileKey`, so onboarding and the You tab read and write the
//  same values.
//
//  Four answers: a name, what they're here for, how they eat, and what
//  they keep off the table. Each of the last three is a set of preset
//  picks plus the person's own words: one line for the first two, any
//  number of short items for the last, kept in one comma-joined string.
//  Preferences the suggestions respect, never rules the app enforces.
//

import Foundation

// MARK: - Keys

enum ProfileKey {
    /// Kept as "displayName" so a name typed into the old You tab carries over.
    static let name = "displayName"
    /// Comma-joined `Goal` raw values.
    static let goals = "profile.goals"
    static let goalCustom = "profile.goalCustom"
    static let diet = "profile.diet"
    static let dietCustom = "profile.dietCustom"
    /// Comma-joined `Avoid` raw values.
    static let avoids = "profile.avoids"
    /// The person's own items, comma-joined; see `ProfileAnswers.list`.
    static let avoidCustom = "profile.avoidCustom"
    static let haptics = "profile.haptics"
    /// Flipped once the intro has been seen through to the end.
    static let didOnboard = "profile.didOnboard"
}

// MARK: - A pickable answer

/// One answer in a profile question: a label and a raw id.
protocol ProfileChoice: RawRepresentable, CaseIterable, Identifiable, Hashable where RawValue == String {
    var label: String { get }
}

extension ProfileChoice {
    var id: String { rawValue }

    /// Round-trips a multi-select through one UserDefaults string.
    static func decode(_ stored: String) -> Set<Self> {
        Set(stored.split(separator: ",").compactMap { Self(rawValue: String($0)) })
    }

    static func encode(_ picks: Set<Self>) -> String {
        allCases.filter(picks.contains).map(\.rawValue).joined(separator: ",")
    }

    /// The chosen labels in menu order.
    static func labels(_ picks: Set<Self>) -> [String] {
        allCases.filter(picks.contains).map(\.label)
    }
}

// MARK: - Onboarding answers

/// "What would you like more of?" Multi-select.
enum Goal: String, ProfileChoice {
    case fuller, steady, cravings, peace, curious

    var label: String {
        switch self {
        case .fuller: "Feeling full for longer"
        case .steady: "Steadier energy all day"
        case .cravings: "Making peace with cravings"
        case .peace: "Eating without the guilt"
        case .curious: "Just curious"
        }
    }

    /// The same wish, phrased for the AI's profile section.
    var aiLabel: String { label.lowercased() }
}

/// "How do you eat?" Single choice among presets.
enum Diet: String, ProfileChoice {
    case everything, vegetarian, vegan, pescatarian

    var label: String {
        switch self {
        case .everything: "A bit of everything"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .pescatarian: "Pescatarian"
        }
    }

    /// What the AI is told. "A bit of everything" is no rule at all; the
    /// others spell out what's off the table, hidden sources included, so
    /// the model never has to guess where the line sits.
    var aiRule: String? {
        switch self {
        case .everything:
            nil
        case .vegetarian:
            "Vegetarian: no meat, poultry, fish or seafood, including stock, gelatin and fish sauce. Eggs and dairy are fine."
        case .vegan:
            "Vegan: no meat, poultry, fish, seafood, eggs, dairy, honey or any other animal product, whey, ghee and gelatin included. "
            + "Anchor with plant proteins (tofu, tempeh, edamame, beans, lentils, hummus, nuts, seeds) and plant-based yogurt, milk and cheese."
        case .pescatarian:
            "Pescatarian: fish and seafood are fine, no other meat or poultry."
        }
    }

    /// The small badge that rides along with suggestions. Nothing for "a
    /// bit of everything": there's no rule to show.
    var badge: (icon: String, label: String)? {
        switch self {
        case .everything: nil
        case .vegetarian, .vegan: ("leaf.fill", label)
        case .pescatarian: ("fish.fill", label)
        }
    }
}

/// "What do you keep off the table?" Multi-select. A preference like
/// the diet pick, not a health record: the app never asks why.
enum Avoid: String, ProfileChoice {
    case nuts, peanuts, dairy, gluten, eggs, shellfish, soy, sesame

    var label: String {
        switch self {
        case .nuts: "Tree nuts"
        case .peanuts: "Peanuts"
        case .dairy: "Dairy"
        case .gluten: "Gluten"
        case .eggs: "Eggs"
        case .shellfish: "Shellfish"
        case .soy: "Soy"
        case .sesame: "Sesame"
        }
    }

    /// What the AI is told, with the places this hides so a "nut butter"
    /// or a "whey" never slips through on a technicality.
    var aiDetail: String {
        switch self {
        case .nuts: "tree nuts (almonds, walnuts, cashews, pistachios, pecans, hazelnuts, macadamia, pine nuts, nut butters, marzipan, pesto, almond milk)"
        case .peanuts: "peanuts (peanut butter, satay, most trail mixes)"
        case .dairy: "dairy (milk, cheese, yogurt, skyr, kefir, cottage cheese, ricotta, butter, cream, whey, ghee, lattes)"
        case .gluten: "gluten (wheat, barley, rye, regular bread, pasta, noodles, crackers, pastry, couscous, seitan, most soy sauce)"
        case .eggs: "eggs (mayo, aioli, egg bites, meringue, most fresh pasta)"
        case .shellfish: "shellfish (shrimp, prawns, crab, lobster, clams, mussels, oysters, scallops, squid)"
        case .soy: "soy (tofu, tempeh, edamame, miso, soy sauce, soy milk, tamari)"
        case .sesame: "sesame (tahini, hummus, halva, sesame oil, seeded bagels)"
        }
    }

    /// The short "No …" chip.
    var badgeLabel: String {
        switch self {
        case .nuts: "No nuts"
        default: "No \(label.lowercased())"
        }
    }
}

// MARK: - Reading answers

enum ProfileAnswers {
    /// Preset labels followed by the person's own line, trimmed. Empty
    /// when nothing was picked or written.
    static func joined(_ labels: [String], custom: String) -> [String] {
        let own = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? labels : labels + [own]
    }

    /// An own-words answer that holds several items ("Cilantro, Mushrooms")
    /// split back into them: trimmed, blanks dropped, repeats folded. A
    /// single line typed before there were chips comes back as one item.
    static func list(_ custom: String) -> [String] {
        var seen = Set<String>()
        var items: [String] = []
        for piece in custom.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let item = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty, seen.insert(item.lowercased()).inserted else { continue }
            items.append(item)
        }
        return items
    }

    /// The other direction, for saving.
    static func encodeList(_ items: [String]) -> String {
        items.joined(separator: ", ")
    }
}

// MARK: - AI profile string

enum ProfileContext {
    /// Whether the app knows how this person eats at all. An answer that
    /// rules nothing out still counts: "a bit of everything" with an empty
    /// off-the-table list is a person saying they're open to anything, and
    /// the built-in ideas are theirs to have. This is false only when
    /// neither question was ever answered, in which case a plate the app
    /// picked on its own would be a guess, and the AI, which is told what
    /// little there is and asks for the rest, is the safer way round.
    static var knowsFoodRules: Bool {
        let defaults = UserDefaults.standard
        if Diet(rawValue: defaults.string(forKey: ProfileKey.diet) ?? "") != nil { return true }
        let dietOwnWords = (defaults.string(forKey: ProfileKey.dietCustom) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !dietOwnWords.isEmpty { return true }
        if !Avoid.decode(defaults.string(forKey: ProfileKey.avoids) ?? "").isEmpty { return true }
        return !ProfileAnswers.list(defaults.string(forKey: ProfileKey.avoidCustom) ?? "").isEmpty
    }

    /// Everything the intro learned, phrased for the AI and passed with
    /// every call, built fresh from whatever's saved. What they're here
    /// for steers the wording; the diet and the foods kept off the table are
    /// hard rules. Empty
    /// when nothing was set, in which case no profile section is sent.
    static func aiProfile() -> String {
        let defaults = UserDefaults.standard
        var lines: [String] = []

        let goals = Goal.decode(defaults.string(forKey: ProfileKey.goals) ?? "")
        let goalWords = ProfileAnswers.joined(
            Goal.allCases.filter(goals.contains).map(\.aiLabel),
            custom: defaults.string(forKey: ProfileKey.goalCustom) ?? ""
        )
        if !goalWords.isEmpty {
            lines.append("Here for: \(goalWords.joined(separator: ", ")).")
        }

        let diet = Diet(rawValue: defaults.string(forKey: ProfileKey.diet) ?? "")
        if let rule = diet?.aiRule {
            lines.append("Diet: \(rule)")
        }
        let dietOwnWords = (defaults.string(forKey: ProfileKey.dietCustom) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !dietOwnWords.isEmpty {
            lines.append("How they eat, in their own words: \(dietOwnWords).")
        }

        let avoids = Avoid.decode(defaults.string(forKey: ProfileKey.avoids) ?? "")
        let avoidWords = Avoid.allCases.filter(avoids.contains).map(\.aiDetail)
            + ProfileAnswers.list(defaults.string(forKey: ProfileKey.avoidCustom) ?? "")
        if !avoidWords.isEmpty {
            lines.append("Avoids: \(avoidWords.joined(separator: "; ")).")
        }
        return lines.joined(separator: "\n")
    }
}
