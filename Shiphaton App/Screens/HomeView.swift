//
//  HomeView.swift
//  Shiphaton App
//
//  Today at a glance: a plain greeting, the hero — today's trio ring, the app's
//  value made visible (fitness-rings style: fills as the day's food brings
//  builders, no food imagery, near-zero text) — a one-tap vibe check,
//  recipe-maker & craving-translator doorways and today's meals.
//  Visual-first, minimal copy, zero judgment. The week's history and
//  patterns live on the Progress tab, not here.
//

import SwiftUI
import SwiftData
import Combine

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.layout) private var layout
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]
    @Query(sort: \EnergyCheck.date, order: .reverse) private var energyChecks: [EnergyCheck]
    @Binding var showLogFlow: Bool
    @Environment(\.scenePhase) private var scenePhase

    @State private var appeared = false
    @State private var activeSheet: HomeSheet?
    @State private var editingEnergy = false
    /// Nudged when a check-in ages out, so the question can come back while
    /// Home is already on screen.
    @State private var checkInClock = Date.now
    /// Both swipe hints retire for good once a meal has actually been
    /// removed: the gesture has been learned, so stop teaching it.
    @AppStorage("didRemoveMeal") private var didRemoveMeal = false

    private let checkInTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum HomeSheet: String, Identifiable {
        case builder, craving
        var id: String { rawValue }
    }

    private var todaysMeals: [Meal] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    /// The most recently logged meal, whenever it was. The hero reflects
    /// this one plate rather than the day's running total.
    private var previousMeal: Meal? { meals.first }

    private var heroCompounds: Set<Compound> {
        previousMeal?.compounds ?? []
    }

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: layout.sectionGap) {
                header
                    .reveal(appeared, order: 0)
                heroCard
                    .reveal(appeared, order: 0.5)
                energyStrip
                    .reveal(appeared, order: 1)
                quickHelp
                    .reveal(appeared, order: 1.5)
                if !todaysMeals.isEmpty {
                    todaySection
                        .reveal(appeared, order: 2)
                }
            }
            .padding(.horizontal, layout.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, layout.tabBarClearance)
            // Tagged outside the padding so the screenshot hook's scroll-to-
            // bottom clears the tab bar instead of parking under it.
            .id("bottom")
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            AuraBackdrop().ignoresSafeArea(edges: .top)
        }
        .background(Palette.canvas)
        .onAppear {
            appeared = true
            #if DEBUG
            // Screenshot hook: launch with "-uisheet builder" or "-uisheet craving".
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-uisheet"), index + 1 < arguments.count {
                activeSheet = HomeSheet(rawValue: arguments[index + 1])
            }
            // Screenshot hook: "-uibottom" scrolls to the last section so the
            // tab-bar clearance can be eyeballed.
            if arguments.contains("-uibottom") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { scroll.scrollTo("bottom", anchor: .bottom) }
                }
            }
            #endif
        }
        .onReceive(checkInTimer) { _ in
            // Only touch state when a check-in actually ages out, so Home
            // isn't re-rendered every minute for nothing.
            if let latest = energyChecks.first,
               Date.now.timeIntervalSince(latest.date) >= Self.checkInWindow,
               checkInClock.timeIntervalSince(latest.date) < Self.checkInWindow {
                checkInClock = .now
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkInClock = .now }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .builder: MealBuilderView().presentationCornerRadius(32)
            case .craving: CravingTranslatorView().presentationCornerRadius(32)
            }
        }
        }
    }

    // MARK: - Header

    private var greeting: (String, String) {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return ("Good morning", "☀️")
        case 12..<17: return ("Good afternoon", "🌤️")
        case 17..<22: return ("Good evening", "🌙")
        default: return ("Still up?", "✨")
        }
    }

    /// Just the greeting. The date said nothing the phone's own clock
    /// doesn't, and it made the first thing you read a fact instead of a
    /// hello.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceS) {
            Text(greeting.0)
                .font(.editorial(32, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(greeting.1)
                .font(.system(size: 24))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    // MARK: - Vibe check

    /// How long an answer stays current. Four hours is about the natural
    /// swing between meals — energy and hunger drift on roughly that cycle —
    /// so the question comes back about three times in a waking day: often
    /// enough to catch a real shift, rare enough that it never nags.
    private static let checkInWindow: TimeInterval = 4 * 60 * 60

    private var currentEnergyCheck: EnergyCheck? {
        energyChecks.first { checkInClock.timeIntervalSince($0.date) < Self.checkInWindow }
    }

    /// One tap, four moods, no numbers — a wellness-style check-in that sits
    /// directly on the canvas (no card). Asks every four hours or so, then
    /// folds into a one-line acknowledgment (tap to change your mind).
    private var energyStrip: some View {
        Group {
            if let check = currentEnergyCheck, !editingEnergy {
                Button {
                    Haptics.soft()
                    editingEnergy = true
                } label: {
                    HStack(spacing: 13) {
                        Text(check.level.emoji)
                            .font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(check.level.headline)
                                .font(.display(15, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text(check.level.response)
                                .font(.display(13, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Palette.canvas))
                    }
                    .softCard(padding: 14)
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                }
                .buttonStyle(BounceStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(check.level.headline). \(check.level.response). Tap to change your energy.")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                VStack(alignment: .leading, spacing: Metrics.spaceM) {
                    Text("How's your energy?")
                        .font(.editorial(18, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: Metrics.spaceS) {
                        ForEach(EnergyLevel.allCases) { level in
                            Button {
                                record(level)
                            } label: {
                                VStack(spacing: 6) {
                                    Text(level.emoji)
                                        .font(.system(size: 26))
                                        .frame(width: 54, height: 54)
                                        .background(
                                            Circle()
                                                .fill(Palette.card)
                                                .shadow(color: Color(hex: "2E3A54").opacity(0.05), radius: 8, y: 3)
                                        )
                                    Text(level.label)
                                        .font(.display(11, weight: .semibold))
                                        .foregroundStyle(Palette.inkSoft)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(BounceStyle())
                            .accessibilityLabel(level.label)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: editingEnergy)
        .animation(.spring(duration: 0.5, bounce: 0.25), value: currentEnergyCheck?.levelRaw)
    }

    private func record(_ level: EnergyLevel) {
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
            if let existing = currentEnergyCheck {
                existing.level = level
                existing.date = .now
            } else {
                modelContext.insert(EnergyCheck(level: level))
            }
            checkInClock = .now
            editingEnergy = false
        }
        Haptics.success()
    }

    // MARK: - Quick help

    /// Two tinted doorway tiles side by side — self-explanatory, no section
    /// label, no descriptions. Their tints sit outside the trio's palette on
    /// purpose: sage and gold already mean fibre and fats in the ring a
    /// screen above, and neither doorway is about a builder.
    private var quickHelp: some View {
        HStack(spacing: Metrics.spaceM) {
            quickHelpTile(emoji: "🧺", title: "Recipe maker", tint: Palette.slateTint, accent: Palette.slate) {
                activeSheet = .builder
            }
            quickHelpTile(emoji: "🍒", title: "Craving translator", tint: Palette.berryTint, accent: Palette.berry) {
                activeSheet = .craving
            }
        }
    }

    private func quickHelpTile(
        emoji: String,
        title: String,
        tint: Color,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(emoji)
                        .font(.system(size: 30))
                        .frame(width: 44, height: 44, alignment: .leading)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Palette.card.opacity(0.65)))
                }
                Text(title)
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .strokeBorder(accent.opacity(0.14), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(BounceStyle())
    }

    // MARK: - Hero: today's trio

    /// The hero is the app's value made visible — the fitness-rings move.
    /// One big trio ring showing which builders the last plate brought:
    /// no food imagery (nothing to crave), near-zero text, additive by
    /// construction — it only ever fills, never fails. Absent segments sit
    /// in their own pastel, an invitation rather than a gap. It sits on the
    /// bare canvas, no card behind it, so the ring is the whole object. It is
    /// a readout, not a button: the camera in the bar is the way to log.
    /// Nothing logged yet has no previous meal to name, so the label falls
    /// back to the day rather than pointing at a plate that isn't there.
    private var heroLabel: String {
        previousMeal == nil ? "TODAY'S TRIO" : "PREVIOUS MEAL'S TRIO"
    }

    private var heroStatus: String {
        if heroCompounds.count == Compound.allCases.count {
            return "Plenty of staying power 💛"
        }
        if heroCompounds.isEmpty {
            return "The day is wide open."
        }
        return "Staying power is building."
    }

    private var heroAccessibilityLabel: String {
        let present = Compound.allCases.filter { heroCompounds.contains($0) }.map(\.label)
        return present.isEmpty
            ? "Today's trio. The day is wide open."
            : "Previous meal's trio: \(present.joined(separator: ", "))"
    }

    private var heroCard: some View {
        VStack(spacing: 22) {
            Text(heroLabel)
                .font(.display(11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Palette.roseDeep)
                .contentTransition(.opacity)
            TrioRing(compounds: heroCompounds, size: layout.heroRing, lineWidth: layout.heroLineWidth, pastelTrack: true)
            // A little more air under the chips than between them, so the
            // status line reads as its own beat rather than a fourth chip.
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    ForEach(Compound.allCases) { compound in
                        CompoundChip(compound: compound, filled: heroCompounds.contains(compound))
                    }
                }
                Text(heroStatus)
                    .font(.editorial(20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel)
        .animation(.spring(duration: 0.6, bounce: 0.25), value: heroCompounds)
    }

    // MARK: - Today

    /// The day's trio state lives in the hero now, so this section is just
    /// the meals themselves. Until the first removal, the header carries a
    /// quiet line naming the swipe, so nothing has to be long-pressed to be
    /// found. The cards themselves stay still: a row that moves on its own
    /// every time Home appears reads as a glitch, not a lesson.
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Today",
                subtitle: didRemoveMeal ? nil : "Swipe a card left to take it back off"
            )
            VStack(spacing: 12) {
                ForEach(todaysMeals) { meal in
                    MealCard(meal: meal) { remove(meal) }
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: todaysMeals.count)
    }

    /// Logged something by mistake? Take it straight back off the day.
    private func remove(_ meal: Meal) {
        Haptics.tap()
        didRemoveMeal = true
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            modelContext.delete(meal)
        }
        // Written on the next turn of the run loop. Autosave can lag behind a
        // swipe by seconds, and a meal removed then left unsaved came back on
        // the next launch, hero ring and all; but saving inside the same turn
        // as the delete leaves the queries on screen showing the old plate.
        DispatchQueue.main.async { try? modelContext.save() }
    }

}

// MARK: - Staggered entrance

private struct Reveal: ViewModifier {
    var shown: Bool
    var order: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .animation(.spring(duration: 0.65, bounce: 0.18).delay(0.07 * order), value: shown)
    }
}

private extension View {
    /// Fade-and-rise entrance, staggered by `order`.
    func reveal(_ shown: Bool, order: Double) -> some View {
        modifier(Reveal(shown: shown, order: order))
    }
}

// MARK: - Meal card

struct MealCard: View {
    var meal: Meal
    /// Off where every card in the list shares one context anyway.
    var showsContext = true
    /// Supplied wherever a meal can be taken back off the day.
    var onRemove: (() -> Void)? = nil

    @State private var showDetail = false

    var body: some View {
        Group {
            if let onRemove {
                SwipeToRemove(onRemove: onRemove) { card }
                    .contextMenu {
                        Button(role: .destructive, action: onRemove) {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .accessibilityAction(named: "Remove") { onRemove() }
            } else {
                card
            }
        }
        .bottomCard(isPresented: $showDetail) {
            MealDetailView(meal: meal)
        }
    }

    private static let anchorSize: CGFloat = 54

    private var card: some View {
        HStack(spacing: 13) {
            anchor
            VStack(alignment: .leading, spacing: 7) {
                plateLine
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if showsContext, let context = meal.context {
                    Text(context.label)
                        .font(.display(11, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Palette.card.opacity(0.75)))
                        .overlay(Capsule().strokeBorder(Palette.hairline.opacity(0.8), lineWidth: 1))
                }
            }
            Spacer(minLength: 8)
            Text(meal.date.formatted(date: .omitted, time: .shortened))
                .font(.display(12, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize()
        }
        .softCard(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            showDetail = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows more about this plate")
    }

    /// Every row starts with the same 54pt anchor, so a day of meals reads as
    /// one column whether or not anything was photographed: the picture when
    /// there is one, otherwise the trio itself, bare on the card at a size you
    /// can actually decode. Moving the ring here also closes the dead gap that
    /// opened up on the right of a short plate line.
    @ViewBuilder private var anchor: some View {
        if let data = meal.photoData, let image = UIImage(data: data) {
            MealThumbnail(image: image, size: Self.anchorSize)
        } else {
            TrioRing(compounds: meal.compounds, size: 44, lineWidth: 5, pastelTrack: true)
                .frame(width: Self.anchorSize, height: Self.anchorSize)
                .accessibilityHidden(true)
        }
    }

    /// Every part of the plate at one size and one weight: what the meal
    /// started as and what was added to it are the same meal, so nothing
    /// here reads as the food plus its fixes. Only the separators recede.
    private var plateLine: Text {
        ([meal.name] + meal.boosts).enumerated().reduce(Text(verbatim: "")) { line, part in
            let piece = Text(part.element)
                .font(.display(15, weight: .semibold))
                .foregroundStyle(Palette.ink)
            guard part.offset > 0 else { return line + piece }
            let dot = Text(verbatim: "  ·  ")
                .font(.display(15, weight: .medium))
                .foregroundStyle(Palette.inkSoft.opacity(0.65))
            return line + dot + piece
        }
    }

}

// MARK: - Meal detail

/// What a card in Today or History opens into: the same plate, given room
/// to breathe. Nothing here is new data, just what the row already holds,
/// laid out so it can't be mistaken for a summary.
struct MealDetailView: View {
    var meal: Meal

    @Environment(\.dismissCard) private var dismiss

    /// A bottom card, cut to its content: it ends where the last row does,
    /// and scrolls only if the plate outgrows the screen.
    var body: some View {
        content
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if let data = meal.photoData, let image = UIImage(data: data) {
                MealThumbnail(image: image, size: 220)
                    .frame(maxWidth: .infinity)
            }
            if !meal.compounds.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Compound.allCases.filter(meal.compounds.contains)) { compound in
                        CompoundChip(compound: compound, filled: true)
                    }
                }
            }
            plate
            making
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        // The card adds the home indicator's strip below this, so the last
        // row needs less of its own; on screen the two ends read even.
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(meal.name)
                    .font(.editorial(24, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                subtitle
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.mist))
            }
            .accessibilityLabel("Close")
        }
    }

    /// When and where on one line: two small facts don't earn two rows, and
    /// the meal time reads better next to the moment than stacked under it.
    private var subtitle: some View {
        HStack(spacing: 6) {
            Text(meal.date.formatted(date: .abbreviated, time: .shortened))
            if let context = meal.context {
                Text(verbatim: "·")
                    .foregroundStyle(Palette.inkSoft.opacity(0.5))
                Text("\(context.emoji) \(context.label)")
            }
        }
        .font(.display(13, weight: .medium))
        .foregroundStyle(Palette.inkSoft)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private static let tile: CGFloat = 34
    private static let gutter: CGFloat = 12

    /// No card of its own: a white panel here would have to end somewhere,
    /// and wherever it ended left a seam of bare sheet under it. The rows sit
    /// straight on the sheet, so the background simply runs to the bottom.
    private var plate: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On the plate")
                .font(.display(12, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
            VStack(alignment: .leading, spacing: 0) {
                itemRow(meal.name, emoji: meal.emoji)
                ForEach(meal.boosts, id: \.self) { boost in
                    // Inset to the words, so the emoji column reads as one
                    // run down the sheet rather than four boxed-off rows.
                    Rectangle()
                        .fill(Palette.hairline.opacity(0.7))
                        .frame(height: 1)
                        .padding(.leading, Self.tile + Self.gutter)
                    itemRow(boost, emoji: "✨")
                }
            }
        }
    }

    /// The making, when the plate came with it. Same numbered steps as the
    /// chef's card in the recipe maker, under the same kind of small label
    /// as "On the plate", so the card reads as one page rather than two.
    /// Nothing at all for a snapped plate or a tapped pantry combo.
    @ViewBuilder
    private var making: some View {
        if !meal.steps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("How to make it")
                    .font(.display(12, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(meal.steps.enumerated()), id: \.offset) { number, step in
                        StepRow(number: number + 1, text: step)
                    }
                }
            }
        }
    }

    private func itemRow(_ name: String, emoji: String) -> some View {
        HStack(spacing: Self.gutter) {
            Text(emoji)
                .font(.system(size: 17))
                .frame(width: Self.tile, height: Self.tile)
            Text(name)
                .font(.display(15, weight: .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Idea card

struct IdeaCard: View {
    var food: Food
    var action: () -> Void

    private let cardWidth: CGFloat = 148

    var body: some View {
        Button(action: action) {
            // Boxless, magazine-style: just the image tile with the words
            // floating beneath it on the canvas.
            VStack(alignment: .leading, spacing: Metrics.spaceS) {
                // Drop an asset named "food-<id>" (e.g. "food-tacos") into the
                // catalog and the tile upgrades from emoji to photography.
                Group {
                    if let photo = UIImage(named: "food-\(food.id)") {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Palette.card, Palette.blush.opacity(0.55)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Palette.hairline.opacity(0.65), lineWidth: 1)
                            )
                            .overlay(
                                Text(food.emoji)
                                    .font(.system(size: 42))
                            )
                    }
                }
                .frame(width: cardWidth, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color(hex: "2E3A54").opacity(0.05), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.glowUp ?? food.name)
                        .font(.display(14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2, reservesSpace: true)
                        .lineSpacing(1.5)
                    Text("Starts with \(food.name.lowercased())")
                        .font(.display(12, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(BounceStyle())
    }
}
