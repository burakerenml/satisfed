//
//  AIModels.swift
//  Shiphaton App
//
//  Decodable shapes for the four bots' JSON responses. Array/string
//  fields decode defensively (missing → empty), since a hiccup in the
//  model's output shouldn't crash a swipe deck mid-session.
//

import Foundation

// MARK: - Bot 1: snack analyzer

struct SnackAnalysis: Decodable {
    struct Item: Decodable {
        let name: String
        let compounds: [String]
    }
    struct Suggestion: Decodable {
        let add: String
        let addsCompounds: [String]
        let why: String
        enum CodingKeys: String, CodingKey { case add, addsCompounds = "adds_compounds", why }
    }
    struct MenuPick: Decodable {
        let item: String
        let compounds: [String]
        let why: String
    }

    let photoType: String
    let identifiedItems: [Item]
    let compoundsPresent: [String]
    let compoundsMissing: [String]
    let comboStatus: String
    let headline: String
    let suggestions: [Suggestion]
    let menuPicks: [MenuPick]
    let orderTip: String
    let coachNote: String

    enum CodingKeys: String, CodingKey {
        case photoType = "photo_type", identifiedItems = "identified_items"
        case compoundsPresent = "compounds_present", compoundsMissing = "compounds_missing"
        case comboStatus = "combo_status", headline, suggestions
        case menuPicks = "menu_picks", orderTip = "order_tip", coachNote = "coach_note"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photoType = try c.decodeIfPresent(String.self, forKey: .photoType) ?? "no_food"
        identifiedItems = try c.decodeIfPresent([Item].self, forKey: .identifiedItems) ?? []
        compoundsPresent = try c.decodeIfPresent([String].self, forKey: .compoundsPresent) ?? []
        compoundsMissing = try c.decodeIfPresent([String].self, forKey: .compoundsMissing) ?? []
        comboStatus = try c.decodeIfPresent(String.self, forKey: .comboStatus) ?? "no_food"
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        suggestions = try c.decodeIfPresent([Suggestion].self, forKey: .suggestions) ?? []
        menuPicks = try c.decodeIfPresent([MenuPick].self, forKey: .menuPicks) ?? []
        orderTip = try c.decodeIfPresent(String.self, forKey: .orderTip) ?? ""
        coachNote = try c.decodeIfPresent(String.self, forKey: .coachNote) ?? ""
    }
}

// MARK: - Bot 3: swipe combo builder

struct SwipeDeckResult: Decodable {
    struct Card: Decodable {
        let item: String
        let emoji: String
        let compounds: [String]
        let hook: String
        let why: String
    }

    let baseCompounds: [String]
    let cards: [Card]

    enum CodingKeys: String, CodingKey { case baseCompounds = "base_compounds", cards }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseCompounds = try c.decodeIfPresent([String].self, forKey: .baseCompounds) ?? []
        cards = try c.decodeIfPresent([Card].self, forKey: .cards) ?? []
    }
}

struct SwipeSummaryResult: Decodable {
    let title: String
    let explanation: String

    enum CodingKeys: String, CodingKey { case title, explanation }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
    }
}

// MARK: - Bot 2: idea generator (recipe maker)

struct GeneratedIdeas: Decodable {
    struct Ingredient: Decodable {
        let item: String
        let compounds: [String]
        let haveIt: Bool
        enum CodingKeys: String, CodingKey { case item, compounds, haveIt = "have_it" }
    }
    struct Combo: Decodable {
        let name: String
        let emoji: String
        let ingredients: [Ingredient]
        let compoundsCovered: [String]
        /// One-sentence summary of the making.
        let how: String
        /// The making, one action per line, in order. Older deployments of
        /// the prompt don't send it; `preparation` fills in from `how`.
        let steps: [String]
        let timeMinutes: Int
        let whyItWorks: String
        enum CodingKeys: String, CodingKey {
            case name, emoji, ingredients, compoundsCovered = "compounds_covered", how, steps
            case timeMinutes = "time_minutes", whyItWorks = "why_it_works"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
            ingredients = (try c.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? [])
                .filter { !$0.item.isEmpty }
            compoundsCovered = try c.decodeIfPresent([String].self, forKey: .compoundsCovered) ?? []
            how = try c.decodeIfPresent(String.self, forKey: .how) ?? ""
            steps = (try c.decodeIfPresent([String].self, forKey: .steps) ?? [])
                .map(Self.unnumbered)
                .filter { !$0.isEmpty }
            timeMinutes = try c.decodeIfPresent(Int.self, forKey: .timeMinutes) ?? 0
            whyItWorks = try c.decodeIfPresent(String.self, forKey: .whyItWorks) ?? ""
        }

        /// What to show under "How to make it": the steps when the chef
        /// sent them, otherwise the summary broken into its sentences, so
        /// there is always something to follow.
        var preparation: [String] {
            if !steps.isEmpty { return steps }
            var sentences: [String] = []
            how.enumerateSubstrings(in: how.startIndex..., options: [.bySentences, .localized]) { piece, _, _, _ in
                let trimmed = piece?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty { sentences.append(trimmed) }
            }
            return sentences
        }

        /// The model sometimes numbers its steps anyway ("1. Blend…").
        /// The screen draws its own numbers, so strip theirs.
        private static func unnumbered(_ step: String) -> String {
            var text = step.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = text.prefix { $0.isNumber }
            if !digits.isEmpty {
                let rest = text.dropFirst(digits.count)
                if let mark = rest.first, ".):".contains(mark) {
                    text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
                }
            }
            return text
        }
    }

    let intro: String
    let combos: [Combo]
    let coachNote: String
    let safetyFallback: Bool

    enum CodingKeys: String, CodingKey { case intro, combos, coachNote = "coach_note", safetyFallback = "safety_fallback" }

    init(intro: String, combos: [Combo], coachNote: String, safetyFallback: Bool) {
        self.intro = intro
        self.combos = combos
        self.coachNote = coachNote
        self.safetyFallback = safetyFallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        combos = try c.decodeIfPresent([Combo].self, forKey: .combos) ?? []
        coachNote = try c.decodeIfPresent(String.self, forKey: .coachNote) ?? ""
        safetyFallback = try c.decodeIfPresent(Bool.self, forKey: .safetyFallback) ?? false
    }

    /// Azure's content filter can block a distressed message before the
    /// model ever runs. Answer supportively, never with a raw error.
    static let supportFallback = GeneratedIdeas(
        intro: "Thank you for sharing that with me, what you're feeling matters. Just so you know, "
             + "no food ever needs to be earned or made up for, and every food can fit. 💛",
        combos: [],
        coachNote: "If food is feeling stressful lately, talking it through with a registered "
                 + "dietitian or someone you trust can really help. I'm here whenever you want "
                 + "cozy snack ideas, no judgment, ever.",
        safetyFallback: true
    )
}

// MARK: - Bot 4: craving translator

/// What the body is plausibly asking for, read from a craving plus context
/// and the person's own logged history. Translation only: the food shelf
/// under it is where "so what do I eat" gets answered.
struct CravingTranslation: Decodable {
    struct Signal: Decodable, Identifiable {
        let name: String
        let emoji: String
        let why: String
        var id: String { name }

        enum CodingKeys: String, CodingKey { case name, emoji, why }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
            why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        }
    }

    let headline: String
    let signals: [Signal]
    /// Short plain phrases: the headline answer of the whole feature.
    let bodyNeeds: [String]
    let bodyTalk: String
    /// Neutral observations about what tends to quiet this kind of craving
    /// over time. Information, never instructions.
    let oftenQuietsIt: [String]
    let worthKnowing: String
    let checkIn: String
    let coachNote: String
    let safetyFallback: Bool

    enum CodingKeys: String, CodingKey {
        case headline, signals, bodyNeeds = "body_needs", bodyTalk = "body_talk"
        case oftenQuietsIt = "often_quiets_it"
        case worthKnowing = "worth_knowing", checkIn = "check_in", coachNote = "coach_note"
        case safetyFallback = "safety_fallback"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        signals = (try c.decodeIfPresent([Signal].self, forKey: .signals) ?? []).filter { !$0.name.isEmpty }
        bodyNeeds = (try c.decodeIfPresent([String].self, forKey: .bodyNeeds) ?? []).filter { !$0.isEmpty }
        bodyTalk = try c.decodeIfPresent(String.self, forKey: .bodyTalk) ?? ""
        oftenQuietsIt = (try c.decodeIfPresent([String].self, forKey: .oftenQuietsIt) ?? []).filter { !$0.isEmpty }
        worthKnowing = try c.decodeIfPresent(String.self, forKey: .worthKnowing) ?? ""
        checkIn = try c.decodeIfPresent(String.self, forKey: .checkIn) ?? ""
        coachNote = try c.decodeIfPresent(String.self, forKey: .coachNote) ?? ""
        safetyFallback = try c.decodeIfPresent(Bool.self, forKey: .safetyFallback) ?? false
    }
}
