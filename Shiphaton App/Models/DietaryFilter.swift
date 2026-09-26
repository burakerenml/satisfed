//
//  DietaryFilter.swift
//  Shiphaton App
//
//  The on-device safety net under the profile: a food name is checked
//  against what the person said they don't eat before it can be dealt as
//  a suggestion. The AI gets the same rules in words and honours them;
//  this catches the card that slips through anyway, and it is the only
//  guard the offline deck has.
//
//  Names are matched as whole words ("nut" never fires on "coconut" or
//  "peanut"), and plant milks and nut butters are read for what they are
//  rather than for the word "milk" or "butter" in them.
//

import Foundation

enum DietaryFilter {

    /// True when nothing the person avoids shows up in the name.
    static func allows(_ name: String) -> Bool {
        allows(name, rules: Rules.current())
    }

    /// The same check for a whole list, keeping order.
    static func keep<T>(_ items: [T], name: (T) -> String) -> [T] {
        let rules = Rules.current()
        return items.filter { allows(name($0), rules: rules) }
    }

    /// True only when every line clears. For a card that names a dish and
    /// lists what goes in it, an off-limits piece buried in the list is as
    /// much a problem as one in the title, so the whole card is judged on
    /// all of its parts at once.
    static func allows(all parts: [String]) -> Bool {
        let rules = Rules.current()
        guard !rules.isEmpty else { return true }
        return parts.allSatisfy { allows($0, rules: rules) }
    }

    /// The many-parts check for a whole list, keeping order.
    static func keep<T>(_ items: [T], parts: (T) -> [String]) -> [T] {
        let rules = Rules.current()
        guard !rules.isEmpty else { return items }
        return items.filter { item in parts(item).allSatisfy { allows($0, rules: rules) } }
    }

    // MARK: - Rules

    struct Rules {
        var groups: [Group] = []
        /// Words from the person's own "something else" lines.
        var ownWords: [String] = []

        var isEmpty: Bool { groups.isEmpty && ownWords.isEmpty }

        static func current() -> Rules {
            let defaults = UserDefaults.standard
            var rules = Rules()

            switch Diet(rawValue: defaults.string(forKey: ProfileKey.diet) ?? "") {
            case .vegetarian: rules.groups += [.meat, .seafood]
            case .vegan: rules.groups += [.meat, .seafood, .eggs, .dairy, .honey]
            case .pescatarian: rules.groups += [.meat]
            case .everything, .none: break
            }

            for avoid in Avoid.decode(defaults.string(forKey: ProfileKey.avoids) ?? "") {
                switch avoid {
                case .nuts: rules.groups.append(.treeNuts)
                case .peanuts: rules.groups.append(.peanuts)
                case .dairy: rules.groups.append(.dairy)
                case .gluten: rules.groups.append(.gluten)
                case .eggs: rules.groups.append(.eggs)
                case .shellfish: rules.groups.append(.shellfish)
                case .soy: rules.groups.append(.soy)
                case .sesame: rules.groups.append(.sesame)
                }
            }

            rules.ownWords = words(in: defaults.string(forKey: ProfileKey.avoidCustom) ?? "")
            return rules
        }

        /// A typed line like "mushrooms and cilantro" becomes the words
        /// worth matching on; filler words are dropped.
        private static func words(in text: String) -> [String] {
            let filler: Set<String> = ["and", "or", "no", "not", "any", "the", "all", "also", "of", "with", "to", "a", "an", "i", "im", "am", "dont", "don't", "eat", "like", "really", "much"]
            return text.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count >= 3 && !filler.contains($0) }
        }
    }

    enum Group {
        case meat, seafood, shellfish, eggs, dairy, honey, treeNuts, peanuts, gluten, soy, sesame

        /// Whole words and phrases that give the group away.
        var words: [String] {
            switch self {
            case .meat:
                ["chicken", "turkey", "beef", "pork", "ham", "bacon", "jerky", "steak", "lamb", "sausage", "sausages",
                 "salami", "pepperoni", "prosciutto", "chorizo", "meat", "meats", "meatball", "meatballs", "rotisserie",
                 "patty", "patties", "hot dog", "hotdog", "kebab", "shawarma", "pastrami", "duck", "veal", "mince",
                 "ribs", "wings", "burger", "gelatin", "gelatine", "bone broth", "chicken broth", "beef broth"]
            case .seafood:
                ["fish", "tuna", "salmon", "sardine", "sardines", "anchovy", "anchovies", "mackerel", "cod", "tilapia",
                 "trout", "seafood", "fish sauce", "sushi", "surimi"] + Group.shellfish.words
            case .shellfish:
                ["shrimp", "shrimps", "prawn", "prawns", "crab", "lobster", "clam", "clams", "mussel", "mussels",
                 "oyster", "oysters", "scallop", "scallops", "squid", "calamari", "crawfish", "crayfish", "shellfish"]
            case .eggs:
                ["egg", "eggs", "omelet", "omelette", "frittata", "mayo", "mayonnaise", "aioli", "meringue", "egg bites"]
            case .dairy:
                ["milk", "cheese", "cheeses", "yogurt", "yoghurt", "skyr", "kefir", "ricotta", "mozzarella", "parmesan",
                 "feta", "cheddar", "brie", "halloumi", "paneer", "labneh", "cream", "butter", "whey", "ghee", "froyo",
                 "latte", "cappuccino", "ice cream", "milkshake", "custard", "queso", "burrata", "mascarpone"]
            case .honey:
                ["honey"]
            case .treeNuts:
                ["almond", "almonds", "walnut", "walnuts", "cashew", "cashews", "pistachio", "pistachios", "pecan",
                 "pecans", "hazelnut", "hazelnuts", "macadamia", "macadamias", "brazil nut", "brazil nuts", "pine nut",
                 "pine nuts", "nut", "nuts", "nut butter", "trail mix", "marzipan", "praline", "pesto", "nutella"]
            case .peanuts:
                ["peanut", "peanuts", "peanut butter", "pb", "satay", "groundnut", "groundnuts"]
            case .gluten:
                ["bread", "toast", "bagel", "bagels", "wheat", "pasta", "noodle", "noodles", "ramen", "cracker",
                 "crackers", "croissant", "croissants", "pastry", "pastries", "pita", "naan", "tortilla", "tortillas",
                 "wrap", "wraps", "couscous", "bulgur", "seitan", "barley", "rye", "pretzel", "pretzels", "cereal",
                 "granola", "cookie", "cookies", "cake", "muffin", "muffins", "pancake", "pancakes", "waffle",
                 "waffles", "pizza", "biscuit", "biscuits", "flour", "breadcrumbs", "croutons", "soy sauce"]
            case .soy:
                ["soy", "soya", "soybeans", "tofu", "tempeh", "edamame", "miso", "soy sauce", "soy milk", "tamari",
                 "natto", "teriyaki"]
            case .sesame:
                ["sesame", "tahini", "hummus", "halva", "halvah", "zaatar", "za'atar"]
            }
        }

        /// Phrases that clear a name of this group even though one of its
        /// words appears: "oat milk" is not dairy, "peanut butter" is not
        /// a tree nut, "corn tortilla" has no gluten.
        var exceptions: [String] {
            switch self {
            case .dairy:
                ["oat milk", "soy milk", "almond milk", "coconut milk", "cashew milk", "rice milk", "pea milk",
                 "plant milk", "plant-based", "plant based", "dairy-free", "dairy free", "non-dairy", "nondairy",
                 "vegan", "nut butter", "peanut butter", "almond butter", "cashew butter", "seed butter",
                 "sunflower butter", "sunflower seed butter", "cocoa butter", "apple butter", "coconut cream",
                 "cashew cream", "oat cream", "coconut yogurt", "soy yogurt", "almond yogurt", "oat latte",
                 "soy latte", "almond latte", "coconut latte"]
            case .treeNuts:
                ["peanut", "peanuts", "peanut butter", "coconut", "nutmeg", "nut-free", "nut free"]
            case .gluten:
                ["gluten-free", "gluten free", "rice noodles", "rice noodle", "corn tortilla", "corn tortillas",
                 "buckwheat", "rice cakes", "rice cake", "lettuce wrap", "lettuce wraps", "oat"]
            case .seafood, .shellfish:
                ["fish-free", "fish free", "vegan"]
            case .meat:
                ["plant-based", "plant based", "vegan", "veggie burger", "veggie patty", "bean burger", "meat-free",
                 "meat free", "meatless", "vegetarian"]
            case .eggs:
                ["eggless", "egg-free", "egg free", "vegan", "eggplant"]
            case .soy:
                ["soy-free", "soy free"]
            case .honey, .peanuts, .sesame:
                []
            }
        }
    }

    // MARK: - Matching

    private static func allows(_ name: String, rules: Rules) -> Bool {
        guard !rules.isEmpty else { return true }
        let text = padded(name)
        for group in rules.groups {
            if group.exceptions.contains(where: { text.contains(" \($0) ") }) { continue }
            if group.words.contains(where: { text.contains(" \($0) ") }) { return false }
        }
        for word in rules.ownWords where text.contains(" \(word) ") || text.contains(" \(word)s ") {
            return false
        }
        return true
    }

    /// Lowercased, accents folded, punctuation turned into word breaks,
    /// and a space at each end so every word has a boundary to match on.
    private static func padded(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var out = " "
        for character in folded {
            if character.isLetter || character == "'" {
                out.append(character)
            } else if character == "-" {
                out.append(character)
            } else {
                out.append(" ")
            }
        }
        // Hyphenated words match both ways: "dairy-free" and "dairy free".
        out = out.replacingOccurrences(of: "-", with: " ") + " "
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out
    }
}
