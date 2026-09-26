//
//  FoodLibrary.swift
//  Shiphaton App
//
//  A small on-device knowledge base: common foods people crave or
//  simply have to eat, what satisfaction builders each already brings,
//  and warm, additive suggestions to complete it. Add, never subtract.
//

import Foundation

struct Food: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    /// Builders this food already covers on its own.
    let has: Set<Compound>
    /// Curated boosts that go especially well with this food.
    let pairings: [Boost]
    /// The finished plate, e.g. "Cookies & cream froyo bowl".
    let glowUp: String?

    init(_ id: String, _ name: String, _ emoji: String, has: Set<Compound>, pairings: [Boost] = [], glowUp: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.has = has
        self.pairings = pairings
        self.glowUp = glowUp
    }
}

struct Boost: Identifiable, Hashable {
    let name: String
    let emoji: String
    /// Builders this boost adds.
    let adds: Set<Compound>

    var id: String { name }

    init(_ name: String, _ emoji: String, adds: Set<Compound>) {
        self.name = name
        self.emoji = emoji
        self.adds = adds
    }
}

enum FoodLibrary {

    // MARK: - Quick-pick foods (cravings & have-to-eats)

    static let foods: [Food] = [
        Food("chocolate", "Chocolate", "🍫", has: [.fats],
             pairings: [
                Boost("Protein oatmeal", "🥣", adds: [.protein, .fibre]),
                Boost("Berries", "🫐", adds: [.fibre]),
                Boost("A handful of almonds", "🌰", adds: [.fats, .fibre]),
                Boost("Greek yogurt", "🥛", adds: [.protein]),
             ],
             glowUp: "Chocolate berry yogurt bowl"),
        Food("cookies", "Cookies", "🍪", has: [],
             pairings: [
                Boost("Frozen banana", "🍌", adds: [.fibre]),
                Boost("Cottage cheese", "🥛", adds: [.protein]),
                Boost("Peanut butter", "🥜", adds: [.fats, .protein]),
             ],
             glowUp: "Cookies & cream protein froyo"),
        Food("chips", "Chips", "🥔", has: [],
             pairings: [
                Boost("Greek yogurt dip", "🥣", adds: [.protein]),
                Boost("Crunchy veggies", "🥕", adds: [.fibre]),
                Boost("Guacamole", "🥑", adds: [.fats, .fibre]),
             ],
             glowUp: "Crunchy snack plate"),
        Food("icecream", "Ice cream", "🍦", has: [],
             pairings: [
                Boost("Berries", "🫐", adds: [.fibre]),
                Boost("Chopped nuts", "🌰", adds: [.fats, .protein]),
                Boost("Greek yogurt swirl", "🥛", adds: [.protein]),
             ],
             glowUp: "Sundae with the good stuff"),
        Food("pizza", "Pizza", "🍕", has: [.protein, .fats],
             pairings: [
                Boost("Side salad", "🥗", adds: [.fibre]),
                Boost("Grilled chicken on top", "🍗", adds: [.protein]),
                Boost("Roasted peppers", "🫑", adds: [.fibre]),
             ],
             glowUp: "Loaded pizza & salad plate"),
        Food("ramen", "Instant noodles", "🍜", has: [],
             pairings: [
                Boost("Shrimp or soft egg", "🍤", adds: [.protein]),
                Boost("Bok choy & peppers", "🥬", adds: [.fibre]),
                Boost("Coconut milk splash", "🥥", adds: [.fats]),
             ],
             glowUp: "Coconut shrimp noodle bowl"),
        Food("pasta", "Pasta", "🍝", has: [],
             pairings: [
                Boost("Chicken or white beans", "🍗", adds: [.protein]),
                Boost("Sautéed veggies", "🥦", adds: [.fibre]),
                Boost("Olive oil & parmesan", "🫒", adds: [.fats]),
             ],
             glowUp: "Trattoria-worthy bowl"),
        Food("poptart", "Pop-Tarts", "🧇", has: [],
             pairings: [
                Boost("Greek yogurt", "🥛", adds: [.protein]),
                Boost("Berries", "🫐", adds: [.fibre]),
                Boost("Cashews", "🌰", adds: [.fats]),
             ],
             glowUp: "Pop-tart yogurt bowl"),
        Food("frappuccino", "Frappuccino", "🧋", has: [],
             pairings: [
                Boost("Egg bites", "🥚", adds: [.protein]),
                Boost("Avocado spread", "🥑", adds: [.fats, .fibre]),
             ],
             glowUp: "Balanced coffee-run snack"),
        Food("fries", "Fries", "🍟", has: [],
             pairings: [
                Boost("Burger patty or grilled chicken", "🍔", adds: [.protein]),
                Boost("Side of slaw or salad", "🥗", adds: [.fibre]),
             ],
             glowUp: "Fries, but make it a meal"),
        Food("candy", "Candy", "🍬", has: [],
             pairings: [
                Boost("A cheese stick", "🧀", adds: [.protein, .fats]),
                Boost("An apple", "🍎", adds: [.fibre]),
                Boost("Pistachios", "🌰", adds: [.fats, .protein]),
             ],
             glowUp: "Sweet & steady snack plate"),
        Food("pastry", "Croissant / pastry", "🥐", has: [],
             pairings: [
                Boost("A latte or two eggs", "☕️", adds: [.protein]),
                Boost("Fresh fruit", "🍊", adds: [.fibre]),
             ],
             glowUp: "Café breakfast, complete"),
        Food("beans", "Beans", "🫘", has: [.protein, .fibre],
             pairings: [
                Boost("Avocado or olive oil", "🥑", adds: [.fats]),
                Boost("Rice & salsa", "🍚", adds: [.fibre]),
                Boost("A fried egg on top", "🍳", adds: [.protein, .fats]),
             ],
             glowUp: "Cozy bean bowl"),
        Food("burger", "Burger", "🍔", has: [.protein],
             pairings: [
                Boost("Extra veggies on it", "🍅", adds: [.fibre]),
                Boost("Side salad or slaw", "🥗", adds: [.fibre]),
             ],
             glowUp: "The full burger moment"),
        Food("tacos", "Tacos", "🌮", has: [.protein, .fats],
             pairings: [
                Boost("Black beans", "🫘", adds: [.fibre, .protein]),
                Boost("Guac & pico", "🥑", adds: [.fats, .fibre]),
             ],
             glowUp: "Taco night, upgraded"),
        Food("cereal", "Cereal", "🥣", has: [.fibre],
             pairings: [
                Boost("Milk or Greek yogurt", "🥛", adds: [.protein]),
                Boost("Chia or hemp seeds", "🌱", adds: [.fats, .fibre]),
                Boost("Sliced banana", "🍌", adds: [.fibre]),
             ],
             glowUp: "Cereal that holds you over"),
        Food("toast", "Toast / bagel", "🥯", has: [],
             pairings: [
                Boost("Eggs or smoked salmon", "🍳", adds: [.protein, .fats]),
                Boost("Avocado", "🥑", adds: [.fats, .fibre]),
                Boost("Cottage cheese & tomato", "🍅", adds: [.protein, .fibre]),
             ],
             glowUp: "Deli-counter toast"),
        Food("friedchicken", "Fried chicken", "🍗", has: [.protein, .fats],
             pairings: [
                Boost("Slaw or a side salad", "🥗", adds: [.fibre]),
                Boost("Corn or beans", "🌽", adds: [.fibre]),
             ],
             glowUp: "Fried chicken plate, rounded out"),
        Food("hotdog", "Hot dog", "🌭", has: [.protein, .fats],
             pairings: [
                Boost("Sauerkraut or slaw", "🥬", adds: [.fibre]),
                Boost("Crunchy veggies on the side", "🥕", adds: [.fibre]),
             ],
             glowUp: "Ballpark plate, done right"),
        Food("sandwich", "Sandwich", "🥪", has: [.protein],
             pairings: [
                Boost("Extra greens in it", "🥬", adds: [.fibre]),
                Boost("Avocado", "🥑", adds: [.fats, .fibre]),
             ],
             glowUp: "Deli sandwich, fully loaded"),
        Food("wrap", "Wrap / burrito", "🌯", has: [.protein],
             pairings: [
                Boost("Black beans & rice", "🫘", adds: [.fibre, .protein]),
                Boost("Guac & pico", "🥑", adds: [.fats, .fibre]),
             ],
             glowUp: "Burrito with everything"),
        Food("kebab", "Kebab / shawarma", "🥙", has: [.protein, .fats],
             pairings: [
                Boost("Salad & pickles", "🥗", adds: [.fibre]),
                Boost("Hummus on the side", "🥣", adds: [.fats, .fibre]),
             ],
             glowUp: "Kebab plate, complete"),
        Food("sushi", "Sushi", "🍣", has: [.protein, .fats],
             pairings: [
                Boost("Edamame", "🫛", adds: [.fibre, .protein]),
                Boost("Seaweed salad", "🥬", adds: [.fibre]),
             ],
             glowUp: "Sushi set, rounded out"),
        Food("donut", "Donut", "🍩", has: [],
             pairings: [
                Boost("Greek yogurt", "🥛", adds: [.protein]),
                Boost("Fresh fruit", "🍓", adds: [.fibre]),
                Boost("A handful of nuts", "🌰", adds: [.fats]),
             ],
             glowUp: "Donut, with something to hold you"),
        Food("cake", "Cake / dessert", "🍰", has: [.fats],
             pairings: [
                Boost("Greek yogurt", "🥛", adds: [.protein]),
                Boost("Berries", "🫐", adds: [.fibre]),
             ],
             glowUp: "Dessert plate that holds you"),
        Food("rice", "Rice bowl", "🍚", has: [],
             pairings: [
                Boost("Chicken, tofu or egg", "🍗", adds: [.protein]),
                Boost("Stir-fried veggies", "🥦", adds: [.fibre]),
                Boost("Sesame oil drizzle", "🧂", adds: [.fats]),
             ],
             glowUp: "Rice bowl, fully built"),
        Food("eggs", "Eggs", "🍳", has: [.protein, .fats],
             pairings: [
                Boost("Spinach or tomatoes", "🥬", adds: [.fibre]),
                Boost("A slice of toast", "🍞", adds: [.fibre]),
             ],
             glowUp: "The full egg plate"),
        Food("salad", "Salad", "🥗", has: [.fibre],
             pairings: [
                Boost("Chicken, tuna or chickpeas", "🍗", adds: [.protein]),
                Boost("Olive oil & feta", "🫒", adds: [.fats]),
             ],
             glowUp: "Salad that actually fills you"),
        Food("popcorn", "Popcorn", "🍿", has: [.fibre],
             pairings: [
                Boost("A cheese stick", "🧀", adds: [.protein, .fats]),
                Boost("Pistachios", "🌰", adds: [.fats, .protein]),
             ],
             glowUp: "Movie snack, sorted"),
    ]

    // MARK: - Generic boosts, used when a food has no curated pairing left

    static let genericBoosts: [Compound: [Boost]] = [
        .protein: [
            Boost("Greek yogurt", "🥛", adds: [.protein]),
            Boost("A couple of eggs", "🍳", adds: [.protein]),
            Boost("Rotisserie chicken", "🍗", adds: [.protein]),
            Boost("Cottage cheese", "🥣", adds: [.protein]),
        ],
        .fibre: [
            Boost("Berries or an apple", "🫐", adds: [.fibre]),
            Boost("Crunchy veggies", "🥕", adds: [.fibre]),
            Boost("A handful of edamame", "🫛", adds: [.fibre, .protein]),
        ],
        .fats: [
            Boost("Avocado", "🥑", adds: [.fats, .fibre]),
            Boost("Nuts or seeds", "🌰", adds: [.fats]),
            Boost("Olive oil drizzle", "🫒", adds: [.fats]),
            Boost("Hummus", "🥣", adds: [.fats, .fibre]),
        ],
    ]

    /// Boost ideas for a food: curated pairings first, then generic
    /// fill-ins for any builder still missing.
    static func suggestions(for food: Food) -> [Boost] {
        var result = food.pairings
        let covered = food.has.union(result.flatMap(\.adds))
        for compound in Compound.allCases where !covered.contains(compound) {
            if let generic = genericBoosts[compound]?.first(where: { boost in !result.contains(boost) }) {
                result.append(generic)
            }
        }
        return result
    }

    /// Suggestions for a free-typed food we don't recognize.
    static func genericSuggestions() -> [Boost] {
        Compound.allCases.compactMap { genericBoosts[$0]?.first }
    }

    // MARK: - Search

    /// Everything the grid can show: the built-in library plus whatever
    /// was added on this device.
    static var searchable: [Food] {
        CustomFoodStore.all() + foods
    }

    /// Live results for what's being typed, closest first. An empty query
    /// means everything.
    static func matches(_ text: String, in pool: [Food]) -> [Food] {
        NameSearch.matches(text, in: pool, name: \.name)
    }

    /// The one food a free-typed name should build on, if any. Looser
    /// than the grid search on purpose: "leftover pizza" should still
    /// land on pizza.
    static func food(matching text: String) -> Food? {
        let query = normalized(text)
        guard !query.isEmpty else { return nil }
        let pool = searchable
        if let hit = matches(text, in: pool).first { return hit }
        return pool.first { query.contains(normalized($0.name)) }
    }

    private static func normalized(_ text: String) -> String {
        NameSearch.normalized(text)
    }
}

// MARK: - Name search

/// The one way anything in the app searches a list by name, so the food
/// grid and the recipe maker's ingredients behave identically.
enum NameSearch {

    /// Closest first: names that start with the query, then names whose
    /// later words do, then a plain contains. An empty query means
    /// everything, in the order it came in.
    static func matches<T>(_ text: String, in pool: [T], name: (T) -> String) -> [T] {
        let query = normalized(text)
        guard !query.isEmpty else { return pool }
        var starts: [T] = []
        var word: [T] = []
        var loose: [T] = []
        for item in pool {
            let candidate = normalized(name(item))
            if candidate.hasPrefix(query) {
                starts.append(item)
            } else if candidate.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
                word.append(item)
            } else if candidate.contains(query) {
                loose.append(item)
            }
        }
        return starts + word + loose
    }

    /// Case- and accent-insensitive, with the slashes in names like
    /// "Wrap / burrito" reading as ordinary word breaks.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "/", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
