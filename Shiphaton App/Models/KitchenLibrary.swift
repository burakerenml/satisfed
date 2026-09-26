//
//  KitchenLibrary.swift
//  Shiphaton App
//
//  The recipe maker's knowledge base: everyday ingredients and the
//  cozy combos they unlock. A combo's builders are simply the union of
//  what its ingredients bring — presence only, never amounts.
//

import Foundation

struct Ingredient: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    /// Builders this ingredient brings to a plate.
    let adds: Set<Compound>

    init(_ id: String, _ name: String, _ emoji: String, adds: Set<Compound>) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.adds = adds
    }
}

/// The two optional questions the recipe maker asks before it deals
/// ideas. Both narrow what's offered; neither is required.
enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    /// What the chef is told.
    var brief: String {
        switch self {
        case .breakfast: "We're making breakfast."
        case .lunch: "We're making lunch."
        case .dinner: "We're making dinner."
        case .snack: "We're making a snack."
        }
    }
}

enum PrepTime: String, CaseIterable, Identifiable {
    case none, five, fifteen, thirty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No cooking"
        case .five: "5 min"
        case .fifteen: "15 min"
        case .thirty: "30 min+"
        }
    }

    /// The most minutes a built-in combo may take to still be offered.
    var limit: Int {
        switch self {
        case .none: 0
        case .five: 5
        case .fifteen: 15
        case .thirty: Int.max
        }
    }

    /// What the chef is told.
    var brief: String {
        switch self {
        case .none: "No cooking at all, assemble only, nothing on the stove."
        case .five: "I have about five minutes, so keep it quick."
        case .fifteen: "I have about fifteen minutes, a little cooking is fine."
        case .thirty: "I have half an hour or more and I'm happy to cook."
        }
    }
}

struct KitchenCombo: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    /// Ingredient ids required to unlock this combo.
    let needs: [String]
    /// Honest hands-on time. Zero means nothing gets cooked, just put
    /// together.
    let minutes: Int
    /// When this plate feels at home. Empty means any time.
    let slots: Set<MealSlot>

    init(_ id: String, _ name: String, _ emoji: String, needs: [String], minutes: Int = 5, slots: Set<MealSlot> = []) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.needs = needs
        self.minutes = minutes
        self.slots = slots
    }
}

enum KitchenLibrary {

    static let ingredients: [Ingredient] = [
        // Anchors
        Ingredient("eggs", "Eggs", "🍳", adds: [.protein]),
        Ingredient("yogurt", "Greek yogurt", "🥛", adds: [.protein]),
        Ingredient("chicken", "Chicken", "🍗", adds: [.protein]),
        Ingredient("fish", "Fish", "🐟", adds: [.protein, .fats]),
        Ingredient("tuna", "Canned tuna", "🥫", adds: [.protein]),
        Ingredient("shrimp", "Shrimp", "🦐", adds: [.protein]),
        Ingredient("beef", "Beef", "🥩", adds: [.protein]),
        Ingredient("tofu", "Tofu", "🍲", adds: [.protein]),
        Ingredient("cottage", "Cottage cheese", "🥣", adds: [.protein]),
        Ingredient("cheese", "Cheese", "🧀", adds: [.protein, .fats]),
        Ingredient("beans", "Beans", "🫘", adds: [.protein, .fibre]),
        Ingredient("lentils", "Lentils", "🥘", adds: [.protein, .fibre]),
        Ingredient("edamame", "Edamame", "🫛", adds: [.protein, .fibre]),
        // Bases
        Ingredient("rice", "Rice", "🍚", adds: []),
        Ingredient("pasta", "Pasta", "🍝", adds: []),
        Ingredient("bread", "Bread", "🍞", adds: [.fibre]),
        Ingredient("tortillas", "Tortillas", "🌮", adds: []),
        Ingredient("oats", "Oats", "🌾", adds: [.fibre]),
        Ingredient("potatoes", "Potatoes", "🥔", adds: [.fibre]),
        Ingredient("sweetpotato", "Sweet potato", "🍠", adds: [.fibre]),
        // Fibre
        Ingredient("veggies", "Veggies", "🥦", adds: [.fibre]),
        Ingredient("greens", "Salad greens", "🥬", adds: [.fibre]),
        Ingredient("tomatoes", "Tomatoes", "🍅", adds: [.fibre]),
        Ingredient("mushrooms", "Mushrooms", "🍄", adds: [.fibre]),
        Ingredient("onion", "Onion & garlic", "🧅", adds: []),
        Ingredient("berries", "Berries", "🫐", adds: [.fibre]),
        Ingredient("banana", "Bananas", "🍌", adds: [.fibre]),
        Ingredient("apples", "Apples", "🍎", adds: [.fibre]),
        Ingredient("popcorn", "Popcorn", "🍿", adds: [.fibre]),
        // Fats
        Ingredient("avocado", "Avocado", "🥑", adds: [.fats, .fibre]),
        Ingredient("pb", "Peanut butter", "🥜", adds: [.fats, .protein]),
        Ingredient("nuts", "Nuts & seeds", "🌰", adds: [.fats]),
        Ingredient("oliveoil", "Olive oil", "🫒", adds: [.fats]),
        Ingredient("butter", "Butter", "🧈", adds: [.fats]),
        Ingredient("chocolate", "Dark chocolate", "🍫", adds: [.fats]),
        Ingredient("hummus", "Hummus", "🧆", adds: [.fats, .fibre]),
    ]

    static let combos: [KitchenCombo] = [
        KitchenCombo("scramble", "Veggie scramble plate", "🍳", needs: ["eggs", "veggies"], minutes: 10, slots: [.breakfast, .lunch]),
        KitchenCombo("yogurtbowl", "Berry yogurt bowl", "🫐", needs: ["yogurt", "berries", "nuts"], minutes: 0, slots: [.breakfast, .snack]),
        KitchenCombo("beanbowl", "Cozy bean & rice bowl", "🫘", needs: ["beans", "rice"], minutes: 15, slots: [.lunch, .dinner]),
        KitchenCombo("pastanight", "Trattoria pasta night", "🍝", needs: ["pasta", "chicken", "veggies"], minutes: 25, slots: [.dinner]),
        KitchenCombo("avotoast", "Loaded avo toast", "🥑", needs: ["bread", "avocado", "eggs"], minutes: 10, slots: [.breakfast, .lunch]),
        KitchenCombo("wrap", "Big deli wrap", "🌮", needs: ["tortillas", "chicken", "greens"], minutes: 5, slots: [.lunch, .dinner]),
        KitchenCombo("snackplate", "Snack plate supreme", "🧀", needs: ["cheese", "berries", "nuts"], minutes: 0, slots: [.snack]),
        KitchenCombo("pboats", "PB banana oats", "🥣", needs: ["oats", "pb", "banana"], minutes: 5, slots: [.breakfast, .snack]),
        KitchenCombo("tunabowl", "Sunny tuna salad bowl", "🥫", needs: ["tuna", "greens", "oliveoil"], minutes: 5, slots: [.lunch]),
        KitchenCombo("hummusplate", "Hummus dip plate", "🧆", needs: ["hummus", "veggies"], minutes: 0, slots: [.snack]),
        KitchenCombo("cloudbowl", "Sweet cottage cloud bowl", "☁️", needs: ["cottage", "berries"], minutes: 0, slots: [.breakfast, .snack]),
        KitchenCombo("salmonplate", "Golden fish & greens plate", "🐟", needs: ["fish", "greens", "oliveoil"], minutes: 15, slots: [.lunch, .dinner]),
        KitchenCombo("shrimpbowl", "Garlicky shrimp rice bowl", "🦐", needs: ["shrimp", "rice", "veggies"], minutes: 15, slots: [.dinner]),
        KitchenCombo("beefpotato", "Steakhouse beef & potato plate", "🥩", needs: ["beef", "potatoes", "veggies"], minutes: 30, slots: [.dinner]),
        KitchenCombo("tofustirfry", "Sizzling tofu stir-fry", "🍲", needs: ["tofu", "veggies", "rice"], minutes: 20, slots: [.lunch, .dinner]),
        KitchenCombo("lentilsoup", "Cozy lentil soup", "🥘", needs: ["lentils", "veggies", "onion"], minutes: 30, slots: [.lunch, .dinner]),
        KitchenCombo("loadedpotato", "Loaded baked potato", "🥔", needs: ["potatoes", "cheese", "beans"], minutes: 15, slots: [.lunch, .dinner]),
        KitchenCombo("sweetpotatobowl", "Sweet potato comfort bowl", "🍠", needs: ["sweetpotato", "beans", "avocado"], minutes: 15, slots: [.lunch, .dinner]),
        KitchenCombo("mushroomomelette", "Mushroom cheese omelette", "🍄", needs: ["eggs", "mushrooms", "cheese"], minutes: 10, slots: [.breakfast, .lunch]),
        KitchenCombo("applepb", "Apple & peanut butter plate", "🍎", needs: ["apples", "pb"], minutes: 0, slots: [.snack]),
        KitchenCombo("popcornmix", "Movie night popcorn mix", "🍿", needs: ["popcorn", "nuts", "chocolate"], minutes: 5, slots: [.snack]),
        KitchenCombo("edamamebowl", "Salty edamame bowl", "🫛", needs: ["edamame", "oliveoil"], minutes: 5, slots: [.snack]),
        KitchenCombo("caprese", "Caprese toast", "🍅", needs: ["bread", "tomatoes", "cheese"], minutes: 5, slots: [.lunch, .snack]),
        KitchenCombo("chocoyogurt", "Chocolate chip yogurt bowl", "🍫", needs: ["yogurt", "chocolate", "banana"], minutes: 0, slots: [.snack, .breakfast]),
    ]

    static func ingredient(_ id: String) -> Ingredient? {
        ingredients.first { $0.id == id }
    }

    /// What the finished combo brings — the union of its ingredients.
    static func compounds(of combo: KitchenCombo) -> Set<Compound> {
        combo.needs.reduce(into: []) { result, id in
            if let ingredient = ingredient(id) {
                result.formUnion(ingredient.adds)
            }
        }
    }
}
