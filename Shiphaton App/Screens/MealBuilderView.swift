//
//  MealBuilderView.swift
//  Shiphaton App
//
//  Recipe maker: tap the ingredients you have and watch meal ideas
//  light up. Add, never subtract, near-misses just ask for one more
//  little thing.
//

import SwiftUI
import SwiftData

struct MealBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selected: Set<String> = []
    @State private var chosenCombo: KitchenCombo?
    /// The shelf is long. Folded, it shows its first few rows and a "see
    /// all" line; a search or a tap on that line shows the lot.
    @State private var showsWholeShelf = false

    // MARK: - Setting the scene (both optional)

    @State private var mealSlot: MealSlot?
    @State private var prepTime: PrepTime?

    // MARK: - Ingredient search

    @State private var ingredientQuery = ""
    /// Ingredients added on this device, sitting ahead of the built-in
    /// ones in the grid. Reloaded whenever one is added.
    @State private var customIngredients: [Ingredient] = CustomIngredientStore.all()
    /// The emoji riding along with an ingredient that's about to be added.
    /// Empty until the person picks one; a basket stands in.
    @State private var newIngredientEmoji = ""

    // MARK: - Combo chef (AI idea generator)

    @State private var pantryQuery = ""
    @State private var aiCombos: [GeneratedIdeas.Combo] = []
    @State private var isAskingAI = false
    @State private var aiNotice: String?
    @State private var aiNoticeKind: NoticeBanner.Kind = .trouble
    @State private var aiTask: Task<Void, Never>?
    /// Which of the chef's cards is open on its ingredients and steps.
    /// One at a time, so the list stays a list.
    @State private var openAICombo: Int?

    /// Everything the grid can show: what was typed in on this device,
    /// then the built-in shelf.
    private var allIngredients: [Ingredient] {
        customIngredients + KitchenLibrary.ingredients
    }

    private var searchQuery: String {
        ingredientQuery.trimmingCharacters(in: .whitespaces)
    }

    /// What the grid shows right now: everything when nothing's typed,
    /// otherwise the matches, closest first.
    private var searchResults: [Ingredient] {
        NameSearch.matches(searchQuery, in: allIngredients, name: \.name)
    }

    /// How many tiles the folded shelf shows: two rows of three, so the
    /// combo chef below is in sight without a scroll.
    private static let foldedShelfCount = 6

    /// Whether the fold applies at all: never mid-search, and never once
    /// the whole shelf is asked for.
    private var shelfIsFolded: Bool {
        !showsWholeShelf && searchQuery.isEmpty && searchResults.count > Self.foldedShelfCount
    }

    /// The tiles on screen. Folded, the first rows plus anything already
    /// tapped further down, so a pick never disappears behind the fold.
    private var visibleIngredients: [Ingredient] {
        guard shelfIsFolded else { return searchResults }
        return searchResults.enumerated()
            .filter { $0.offset < Self.foldedShelfCount || selected.contains($0.element.id) }
            .map(\.element)
    }

    /// Typed-in ingredients live outside the library, so every lookup on a
    /// selected id has to go through here.
    private func ingredient(_ id: String) -> Ingredient? {
        allIngredients.first { $0.id == id }
    }

    /// Combos fully unlocked by what's selected, richest plates first.
    /// A chosen prep time is an honest limit, so plates that take longer
    /// drop out; a chosen meal just moves its plates to the front.
    ///
    /// Nothing at all until the person has told us how they eat. The
    /// built-in plates are fixed and can't be told anything, so with no
    /// answers to work from they'd be guesses; the chef below is told what
    /// there is and can be asked for the rest, so that's the way in.
    private var makeable: [KitchenCombo] {
        guard ProfileContext.knowsFoodRules else { return [] }
        return KitchenLibrary.combos
            .filter { Set($0.needs).isSubset(of: selected) }
            .filter { combo in prepTime.map { combo.minutes <= $0.limit } ?? true }
            .sorted { a, b in
                let aFits = fitsSlot(a), bFits = fitsSlot(b)
                if aFits != bFits { return aFits }
                return KitchenLibrary.compounds(of: a).count > KitchenLibrary.compounds(of: b).count
            }
    }

    private func fitsSlot(_ combo: KitchenCombo) -> Bool {
        guard let mealSlot else { return true }
        return combo.slots.isEmpty || combo.slots.contains(mealSlot)
    }

    /// Combos exactly one ingredient short, shown as a gentle nudge. Held
    /// back, like the plates above, until we know how they eat.
    private var oneAway: [(combo: KitchenCombo, missing: Ingredient)] {
        guard !selected.isEmpty, ProfileContext.knowsFoodRules else { return [] }
        return KitchenLibrary.combos.compactMap { combo in
            let missing = combo.needs.filter { !selected.contains($0) }
            guard missing.count == 1, let ingredient = KitchenLibrary.ingredient(missing[0]),
                  // Never nudge someone toward chicken they don't eat.
                  DietaryFilter.allows(ingredient.name) else { return nil }
            return (combo, ingredient)
        }
    }

    #if DEBUG
    /// Screenshot hook: launch with "-uikitchen eggs,veggies" to preselect.
    private func applyDebugLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uikitchen"), index + 1 < arguments.count {
            selected = Set(arguments[index + 1].split(separator: ",").map(String.init))
        }
    }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Tap what's around and ideas light up as you go.")
                            .font(.display(14, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)

                        sceneRows

                        searchField

                        if searchResults.isEmpty, !searchQuery.isEmpty {
                            addIngredientCard(searchQuery)
                        }

                        ingredientGrid

                        if !makeable.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "You can make")
                                ForEach(makeable) { combo in
                                    comboCard(combo)
                                }
                            }
                            .transition(.opacity.combined(with: .offset(y: 12)))
                        }

                        if !oneAway.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "One little add away", subtitle: "Tap one to borrow the missing piece")
                                ForEach(oneAway, id: \.combo.id) { pair in
                                    nearCard(pair.combo, missing: pair.missing)
                                }
                            }
                            .transition(.opacity.combined(with: .offset(y: 12)))
                        }

                        comboChefSection
                    }
                    .padding(.horizontal, Metrics.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .animation(.spring(duration: 0.45, bounce: 0.2), value: selected)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: chosenCombo)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: mealSlot)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: prepTime)
            .onChange(of: selected) { _, newValue in
                if let combo = chosenCombo, !Set(combo.needs).isSubset(of: newValue) {
                    chosenCombo = nil
                }
            }
            #if DEBUG
            .onAppear(perform: applyDebugLaunchArguments)
            #endif
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Recipe maker")
                        .font(.display(17))
                        .foregroundStyle(Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let combo = chosenCombo {
                    Button {
                        make(combo)
                    } label: {
                        Text("I'm making this 💛")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Metrics.screenMargin)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .offset(y: 12)))
                }
            }
        }
        .onDisappear { aiTask?.cancel() }
        .paywallHost { askComboChef() }
    }

    // MARK: - Setting the scene

    /// Two quiet questions, both optional: which meal, and how long. They
    /// sharpen what's offered below and what the chef is told, and they
    /// read as chips rather than a form so nobody feels asked to fill
    /// anything in.
    private var sceneRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            sceneRow(title: "What are we making?") {
                ForEach(MealSlot.allCases) { slot in
                    SceneChip(label: slot.label, isOn: mealSlot == slot) {
                        mealSlot = mealSlot == slot ? nil : slot
                    }
                }
            }
            sceneRow(title: "How much time?") {
                ForEach(PrepTime.allCases) { time in
                    SceneChip(label: time.label, isOn: prepTime == time) {
                        prepTime = prepTime == time ? nil : time
                    }
                }
            }
        }
    }

    private func sceneRow<Chips: View>(title: String, @ViewBuilder chips: () -> Chips) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.display(11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Palette.inkSoft)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chips()
                }
                .padding(.horizontal, Metrics.screenMargin)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // Bleeds to the screen edges so the last chip can peek in
            // from the side, the way iOS's own chip rows do.
            .padding(.horizontal, -Metrics.screenMargin)
        }
    }

    // MARK: - Ingredients

    private var ingredientGrid: some View {
        VStack(spacing: 12) {
            ingredientTiles
            if shelfIsFolded || (showsWholeShelf && searchQuery.isEmpty) {
                shelfToggle
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: showsWholeShelf)
    }

    /// One quiet line under the folded shelf, and its "fewer" twin once
    /// the whole shelf is out.
    private var shelfToggle: some View {
        Button {
            Haptics.soft()
            showsWholeShelf.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(showsWholeShelf ? "Show fewer" : "See all ingredients")
                    .font(.display(14, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(showsWholeShelf ? 180 : 0))
            }
            .foregroundStyle(Palette.roseDeep)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Palette.card)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            )
        }
        .buttonStyle(BounceStyle())
        .frame(maxWidth: .infinity)
    }

    private var ingredientTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(visibleIngredients) { ingredient in
                let isOn = selected.contains(ingredient.id)
                Button {
                    Haptics.soft()
                    if isOn {
                        selected.remove(ingredient.id)
                    } else {
                        selected.insert(ingredient.id)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(ingredient.emoji)
                            .font(.system(size: 26))
                        Text(ingredient.name)
                            .font(.display(12, weight: .semibold))
                            .foregroundStyle(isOn ? Palette.roseDeep : Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isOn ? Palette.roseTint : Palette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(isOn ? Palette.rose.opacity(0.6) : .clear, lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(TapTileStyle(cornerRadius: 16))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .animation(.spring(duration: 0.35), value: visibleIngredients)
    }

    // MARK: - Search and add

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.inkSoft)
            // Results follow every keystroke, so there's nothing to press.
            TextField("Search your ingredients", text: $ingredientQuery)
                .font(.display(16, weight: .medium))
                .foregroundStyle(Palette.ink)
                .submitLabel(.done)
                .autocorrectionDisabled()
            if !ingredientQuery.isEmpty {
                Button {
                    Haptics.soft()
                    ingredientQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.inkSoft.opacity(0.5))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.card)
        )
    }

    /// Nothing on the shelf matched. Offer to keep it: give it an emoji of
    /// your own if you like, and it joins the grid from here on.
    private func addIngredientCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                emojiTile
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.display(16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("New to us. Tap the tile to give it an emoji, and it's on your shelf next time.")
                        .font(.display(13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                addCustomIngredient(name)
            } label: {
                Text("Tap to add this ingredient")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .softCard(padding: 16)
    }

    /// The new ingredient's emoji, typed straight in: the tile is an
    /// emoji-only text box that opens the emoji keyboard, with a faded
    /// basket showing through until something's picked.
    private var emojiTile: some View {
        ZStack {
            if newIngredientEmoji.isEmpty {
                Text("🧺")
                    .font(.system(size: 30))
                    .opacity(0.35)
                    .allowsHitTesting(false)
            }
            EmojiField(emoji: $newIngredientEmoji)
        }
        .frame(width: 54, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.blush.opacity(0.7))
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "pencil")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Palette.card))
                .offset(x: 4, y: 4)
                .allowsHitTesting(false)
        }
        .animation(.spring(duration: 0.3), value: newIngredientEmoji)
        .accessibilityLabel(newIngredientEmoji.isEmpty ? "Pick an emoji" : "Emoji \(newIngredientEmoji), tap to change")
    }

    /// Keeps a typed ingredient on the device, taps it on, and clears the
    /// search so the whole shelf comes back with it in place.
    private func addCustomIngredient(_ name: String) {
        Haptics.success()
        let added = CustomIngredientStore.add(name: name, emoji: newIngredientEmoji.isEmpty ? "🧺" : newIngredientEmoji)
        customIngredients = CustomIngredientStore.all()
        newIngredientEmoji = ""
        ingredientQuery = ""
        selected.insert(added.id)
    }

    // MARK: - Combos

    private func ingredientLine(_ combo: KitchenCombo) -> String {
        combo.needs.compactMap { KitchenLibrary.ingredient($0)?.name.lowercased() }.joined(separator: " · ")
    }

    private func comboCard(_ combo: KitchenCombo) -> some View {
        let isOn = chosenCombo?.id == combo.id
        return Button {
            Haptics.soft()
            chosenCombo = isOn ? nil : combo
        } label: {
            HStack(spacing: 12) {
                EmojiTile(emoji: combo.emoji, size: 46, background: Palette.canvas)
                VStack(alignment: .leading, spacing: 3) {
                    Text(combo.name)
                        .font(.display(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(ingredientLine(combo))
                        .font(.display(12, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                Spacer()
                TrioRing(compounds: KitchenLibrary.compounds(of: combo), size: 34, lineWidth: 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(isOn ? Palette.rose.opacity(0.6) : .clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(BounceStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func nearCard(_ combo: KitchenCombo, missing: Ingredient) -> some View {
        Button {
            Haptics.tap()
            selected.insert(missing.id)
        } label: {
            HStack(spacing: 12) {
                EmojiTile(emoji: combo.emoji, size: 46, background: Palette.canvas)
                    .opacity(0.75)
                VStack(alignment: .leading, spacing: 3) {
                    Text(combo.name)
                        .font(.display(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("+ just add \(missing.name.lowercased()) \(missing.emoji)")
                        .font(.display(12, weight: .semibold))
                        .foregroundStyle(Palette.honey)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.inkSoft.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.card.opacity(0.7))
            )
        }
        .buttonStyle(BounceStyle())
    }

    // MARK: - Save

    private func make(_ combo: KitchenCombo) {
        let meal = Meal(
            name: combo.name,
            emoji: combo.emoji,
            context: .pantry,
            compounds: KitchenLibrary.compounds(of: combo),
            boosts: combo.needs.compactMap { KitchenLibrary.ingredient($0)?.name }
        )
        modelContext.insert(meal)
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    // MARK: - Combo chef (AI idea generator)

    /// Free-text ask, on top of whatever's tapped above. Purely additive:
    /// the tap-driven combos above never change because of this.
    private var comboChefSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField(chefPlaceholder, text: $pantryQuery)
                    .font(.display(15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .submitLabel(.go)
                    .onSubmit(askComboChef)

                Button(action: askComboChef) {
                    ChefAskButtonLabel(isThinking: isAskingAI)
                }
                .buttonStyle(BounceStyle())
                .disabled(isAskingAI)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))

            // The chef cooks to the profile; the tags under the box say so.
            PreferenceBadges()

            if let aiNotice {
                NoticeBanner(text: aiNotice, kind: aiNoticeKind)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }

            ForEach(Array(aiCombos.enumerated()), id: \.offset) { index, combo in
                aiComboCard(combo, at: index)
            }

            // Last thing in the section, so it sits under whatever the
            // chef just handed over rather than in front of the ask.
            HealthDisclaimer()
                .padding(.top, 2)
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: aiCombos.count)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: openAICombo)
        .animation(.spring(duration: 0.35), value: aiNotice)
    }

    /// The field's hint follows what's already been said above it, so an
    /// empty field with nothing tapped invites a surprise rather than
    /// looking like a required box.
    private var chefPlaceholder: String {
        if selected.isEmpty, mealSlot == nil, prepTime == nil {
            return "Anything goes, or leave it blank"
        }
        return "Anything to add? Optional"
    }

    /// Everything the chef is told, in order: the pantry, the scene, the
    /// person's own words. With none of those, a plain ask for a surprise,
    /// which the profile (diet, foods off the table) still shapes on the server.
    private var chefMessage: String {
        var parts: [String] = []
        let pantryNames = selected.compactMap { ingredient($0)?.name }
        if !pantryNames.isEmpty {
            parts.append("I have: \(pantryNames.joined(separator: ", ")).")
        }
        if let mealSlot { parts.append(mealSlot.brief) }
        if let prepTime { parts.append(prepTime.brief) }
        let trimmed = pantryQuery.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { parts.append(trimmed) }
        if parts.isEmpty {
            parts.append("Surprise me. Pick something cozy from everyday staples, no pantry list from me.")
        } else if pantryNames.isEmpty {
            parts.append("No pantry list from me, use everyday staples.")
        }
        return parts.joined(separator: " ")
    }

    private func askComboChef() {
        guard !isAskingAI else { return }
        Haptics.soft()
        aiNotice = nil
        // A spent free round meets the paywall here, before a spinner
        // that would only end in a refusal.
        if SubscriptionStore.shared.needsSubscription {
            PaywallCenter.shared.request(.blocked)
            return
        }
        if !NetworkMonitor.shared.isOnline {
            aiNoticeKind = .offline
            aiNotice = AIError.offlineMessage
            return
        }
        let message = chefMessage
        isAskingAI = true
        aiTask?.cancel()
        aiTask = Task {
            do {
                let result = try await ComboAIClient.generateIdeas(message: message, profile: ProfileContext.aiProfile())
                guard !Task.isCancelled else { return }
                isAskingAI = false
                if result.safetyFallback {
                    aiNoticeKind = .nudge
                    aiNotice = result.intro
                    aiCombos = []
                } else {
                    // The chef is told the diet and the foods kept off the
                    // table and works inside them; this is the net under
                    // it. An idea is judged on its name and on every piece
                    // that goes in, so one off-limits ingredient takes the
                    // whole card rather than sitting quietly in its list.
                    let combos = DietaryFilter.keep(result.combos, parts: { combo in
                        [combo.name] + combo.ingredients.map(\.item)
                    })
                    openAICombo = nil
                    aiCombos = combos
                    if combos.isEmpty {
                        aiNoticeKind = .nudge
                        // The chef's own intro only fits when it really
                        // came back empty. If the net took everything, that
                        // line would be promising ideas that aren't there.
                        aiNotice = result.combos.isEmpty && !result.intro.isEmpty
                            ? result.intro
                            : "The chef came back empty-handed this time. Tap an ingredient or two and ask again."
                    }
                }
                // The chef's answer is the whole free go, if that's what
                // this was. The paywall follows on the good news, after a
                // beat, the same way it follows the plate summary. Awaited
                // on the chef's own task, and last, so the ideas are on
                // screen first and closing the sheet calls the offer off
                // instead of raising it over whatever came next.
                await offerSubscriptionIfLoopSpent()
            } catch AIError.paywallRequired {
                // The paywall is already on its way up. Saying the chef is
                // unreachable on top of that would just be confusing.
                guard !Task.isCancelled else { return }
                isAskingAI = false
            } catch {
                guard !Task.isCancelled else { return }
                isAskingAI = false
                aiNoticeKind = NoticeBanner.kind(for: error)
                aiNotice = AIError.friendlyMessage(for: error, what: "ask the chef")
            }
        }
    }

    /// One free go is one answer from any AI feature. The gate is asked
    /// again once the chef's ideas are on screen, so the next tap meets
    /// the paywall up front, and the soft offer lands after a beat, once
    /// the ideas have actually been seen.
    private func offerSubscriptionIfLoopSpent() async {
        await SubscriptionStore.shared.refreshGateState()
        guard SubscriptionStore.shared.needsSubscription else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        PaywallCenter.shared.offerAfterFreeLoop()
    }

    /// One of the chef's ideas. Folded: the name, the time, the ring, what
    /// goes in and what it brings. Open: every ingredient marked have or
    /// need, then the making step by step, then the one-line why.
    private func aiComboCard(_ combo: GeneratedIdeas.Combo, at index: Int) -> some View {
        let compounds = Set(combo.compoundsCovered.compactMap { Compound(aiValue: $0) })
        let isOpen = openAICombo == index
        return VStack(alignment: .leading, spacing: 12) {
            // No emoji tile here: the chef's picks read as ideas, not
            // pantry items, so the name carries the card on its own.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(combo.name)
                        .font(.display(16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if combo.timeMinutes > 0 {
                        Text("\(combo.timeMinutes) min")
                            .font(.display(12, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                TrioRing(compounds: compounds, size: 34, lineWidth: 4)
            }

            if !isOpen {
                if !combo.ingredients.isEmpty {
                    Text(combo.ingredients.map(\.item).joined(separator: " · "))
                        .font(.display(13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(2)
                        .transition(.opacity)
                }
                AddsPills(adds: compounds)
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 16) {
                    if !combo.ingredients.isEmpty {
                        aiDetail(title: "What goes in") {
                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(Array(combo.ingredients.enumerated()), id: \.offset) { _, ingredient in
                                    IngredientTag(name: ingredient.item, haveIt: ingredient.haveIt)
                                }
                            }
                        }
                    }
                    let steps = combo.preparation
                    if !steps.isEmpty {
                        aiDetail(title: "How to make it") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(steps.enumerated()), id: \.offset) { number, step in
                                    StepRow(number: number + 1, text: step)
                                }
                            }
                        }
                    }
                    if !combo.whyItWorks.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.honey)
                                .padding(.top, 2)
                            Text(combo.whyItWorks)
                                .font(.display(13, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }

            // The fold, as a quiet row rather than a chevron in a corner,
            // so "how do I make this" is a thing to tap, not to hunt for.
            Button {
                Haptics.soft()
                openAICombo = isOpen ? nil : index
            } label: {
                HStack(spacing: 6) {
                    Text(isOpen ? "Hide the steps" : "How to make it")
                        .font(.display(14, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(Palette.roseDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.canvas)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(BounceStyle())
            .accessibilityLabel(isOpen ? "Hide the ingredients and steps" : "Show the ingredients and steps")

            Button {
                makeAICombo(combo)
            } label: {
                Text("I'm making this 💛")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isOpen ? Palette.rose.opacity(0.35) : .clear, lineWidth: 1.5)
                )
        )
        .transition(.opacity.combined(with: .offset(y: 12)))
    }

    /// A labelled block inside an open chef card, in the same small caps
    /// as the scene rows at the top of the screen.
    private func aiDetail<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.display(11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Palette.inkSoft)
            content()
        }
    }

    private func makeAICombo(_ combo: GeneratedIdeas.Combo) {
        let meal = Meal(
            name: combo.name,
            emoji: combo.emoji,
            context: .pantry,
            compounds: Set(combo.compoundsCovered.compactMap { Compound(aiValue: $0) }),
            boosts: combo.ingredients.map(\.item),
            steps: combo.preparation
        )
        modelContext.insert(meal)
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Chef card pieces

/// One ingredient in an open chef card. A tick for what's already in the
/// kitchen; a honey plus, the same as the "one little add away" cards,
/// for what's still to pick up.
private struct IngredientTag: View {
    var name: String
    var haveIt: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: haveIt ? "checkmark" : "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(haveIt ? Palette.fibre : Palette.honey)
            Text(name)
                .font(.display(12, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(haveIt ? Palette.canvas : Palette.honeyTint)
        )
        .accessibilityLabel(haveIt ? "\(name), you have it" : "\(name), to add")
    }
}

// MARK: - Ask button

/// The round rose button beside the chef's text field. Idle it shows a
/// sparkle. While the chef is thinking it becomes a working hourglass.
private struct ChefAskButtonLabel: View {
    let isThinking: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.roseGradient)
                .shadow(color: Palette.roseDeep.opacity(0.22), radius: 6, y: 3)

            if isThinking {
                ThinkingHourglass()
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .frame(width: 44, height: 44)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: isThinking)
    }
}

/// A real hourglass, on a loop: the sand drains from the top to the bottom,
/// then the glass turns over and drains again. The turn happens while the
/// glyph is unchanged, so it reads as one object being flipped rather than
/// two pictures swapping.
private struct ThinkingHourglass: View {

    /// Six beats: fill top, drain, fill bottom, turn, drain, fill bottom.
    /// The second half is the same three beats seen upside down, so the
    /// symbol names are inverted there.
    private enum Beat: CaseIterable {
        case topA, drainA, bottomA
        case topB, drainB, bottomB

        /// Upright the sand sits where the symbol says. Flipped, the halves
        /// swap, so `tophalf` is the one that reads as sand on the bottom.
        var symbol: String {
            switch self {
            case .topA, .bottomB: "hourglass.tophalf.filled"
            case .drainA, .drainB: "hourglass"
            case .bottomA, .topB: "hourglass.bottomhalf.filled"
            }
        }

        var flipped: Bool {
            switch self {
            case .topA, .drainA, .bottomA: false
            case .topB, .drainB, .bottomB: true
            }
        }

        /// The two beats the glass is being turned over on.
        var isTurn: Bool { self == .topA || self == .topB }
    }

    var body: some View {
        PhaseAnimator(Beat.allCases) { beat in
            Image(systemName: beat.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace.downUp))
                .rotationEffect(.degrees(beat.flipped ? 180 : 0))
        } animation: { beat in
            beat.isTurn
                ? .spring(duration: 0.55, bounce: 0.28)
                : .easeInOut(duration: 0.55)
        }
    }
}

// MARK: - Scene chip

/// One answer in the recipe maker's two optional rows. Tapping the chosen
/// one again clears it, so "no answer" is always one tap away.
private struct SceneChip: View {
    var label: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.soft()
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                action()
            }
        } label: {
            Text(label)
                .font(.display(13, weight: .semibold))
                .foregroundStyle(isOn ? Palette.roseDeep : Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isOn ? Palette.roseTint : Palette.card)
                        .overlay(
                            Capsule().strokeBorder(isOn ? Palette.rose.opacity(0.5) : Palette.hairline, lineWidth: 1)
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(BounceStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
