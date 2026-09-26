//
//  YouView.swift
//  Shiphaton App
//
//  You: the plates built in the recipe maker on a month calendar, the
//  handful of things onboarding learned (all editable), and the two
//  settings the app actually needs. No settings labyrinth.
//

import SwiftUI
import SwiftData
import UIKit

struct YouView: View {
    @Environment(\.layout) private var layout
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]
    @Query private var energyChecks: [EnergyCheck]

    @AppStorage(ProfileKey.name) private var name = ""
    @AppStorage(ProfileKey.goals) private var goalsRaw = ""
    @AppStorage(ProfileKey.goalCustom) private var goalCustom = ""
    @AppStorage(ProfileKey.diet) private var dietRaw = ""
    @AppStorage(ProfileKey.dietCustom) private var dietCustom = ""
    @AppStorage(ProfileKey.avoids) private var avoidsRaw = ""
    @AppStorage(ProfileKey.avoidCustom) private var avoidCustom = ""
    @AppStorage(ProfileKey.haptics) private var haptics = true
    @AppStorage(ProfileKey.didOnboard) private var didOnboard = true

    @State private var activeChoice: YouChoice?
    @State private var showBuilder = false
    @State private var confirmingReset = false
    @State private var showSupport = false
    @State private var store = SubscriptionStore.shared

    private enum YouChoice: String, Identifiable {
        case goal, diet, avoid
        var id: String { rawValue }
    }

    // MARK: - Derived

    private var goals: Set<Goal> { Goal.decode(goalsRaw) }
    private var diet: Diet? { Diet(rawValue: dietRaw) }
    private var avoids: Set<Avoid> { Avoid.decode(avoidsRaw) }

    /// Plates built in the recipe maker, newest first.
    private var recipes: [Meal] {
        meals.filter { $0.context == .pantry }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.sectionGap) {
                recipesSection
                aboutSection
                settingsSection
                footer
            }
            .padding(.horizontal, layout.screenMargin)
            .padding(.top, 18)
            .padding(.bottom, layout.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Palette.canvas)
        .sheet(isPresented: $showBuilder) {
            MealBuilderView().presentationCornerRadius(32)
        }
        // Somewhere for the paywall to appear when it's asked for from
        // here rather than run into mid-flow.
        .paywallHost()
        .bottomCard(item: $activeChoice) { choice in
            switch choice {
            case .goal:
                ChoiceSheet(
                    title: "What would you like more of?",
                    multi: true,
                    selection: Binding(
                        get: { goals },
                        set: { goalsRaw = Goal.encode($0) }
                    ),
                    custom: $goalCustom
                )
            case .diet:
                ChoiceSheet(
                    title: "How do you eat?",
                    selection: singleSelection($dietRaw, as: Diet.self),
                    custom: $dietCustom
                )
            case .avoid:
                ChoiceSheet(
                    title: "What do you keep off the table?",
                    multi: true,
                    grid: true,
                    selection: Binding(
                        get: { avoids },
                        set: { avoidsRaw = Avoid.encode($0) }
                    ),
                    custom: $avoidCustom,
                    customTakesSeveral: true
                )
            }
        }
        .confirmationDialog(
            "Start fresh?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Clear everything I've logged", role: .destructive, action: reset)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Every meal and vibe check goes.")
        }
        #if DEBUG
        .onAppear(perform: applyDebugLaunchArguments)
        #endif
    }

    /// A single-choice answer stored as its raw value. Wrapped as a set so
    /// both kinds of question share one sheet.
    private func singleSelection<Choice: ProfileChoice>(
        _ stored: Binding<String>,
        as _: Choice.Type
    ) -> Binding<Set<Choice>> {
        Binding(
            get: { Choice(rawValue: stored.wrappedValue).map { [$0] } ?? [] },
            set: { stored.wrappedValue = $0.first?.rawValue ?? "" }
        )
    }

    // MARK: - Recipes

    /// The same calendar as Progress, showing only what was built from
    /// what was on hand. Progress keeps every logged meal; this is the
    /// recipe book.
    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Your recipes")
            if recipes.isEmpty {
                // No calendar until there is something to put on it: a month
                // of empty days is not a recipe book.
                emptyRecipes
            } else {
                MealCalendar(
                    meals: recipes,
                    emptyText: "Nothing made on this day.",
                    showsContext: false,
                    onRemove: remove
                )
            }
        }
    }

    private var emptyRecipes: some View {
        Button {
            Haptics.tap()
            showBuilder = true
        } label: {
            HStack(spacing: 14) {
                Text("Build your first recipe")
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.slate)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.slateTint))
            }
            .softCard(padding: 18)
        }
        .buttonStyle(BounceStyle())
    }

    private func remove(_ meal: Meal) {
        Haptics.soft()
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            modelContext.delete(meal)
        }
        // Next turn, not this one: see HomeView.remove.
        DispatchQueue.main.async { try? modelContext.save() }
    }

    // MARK: - About you

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "About you")
            VStack(spacing: 0) {
                nameRow
                divider
                choiceRow(
                    title: "Here for",
                    value: answer(Goal.labels(goals), custom: goalCustom),
                    placeholder: "Pick one"
                ) { activeChoice = .goal }
                divider
                choiceRow(
                    title: "How you eat",
                    value: answer([diet?.label].compactMap { $0 }, custom: dietCustom),
                    placeholder: "Pick one"
                ) { activeChoice = .diet }
                divider
                choiceRow(
                    title: "Off the table",
                    value: answer(Avoid.labels(avoids) + ProfileAnswers.list(avoidCustom), custom: ""),
                    placeholder: "Nothing"
                ) { activeChoice = .avoid }
                divider
                membershipRow
            }
            .softCard(padding: 8)
        }
    }

    /// Where they stand, stated plainly and never as a nudge: the selling
    /// happens in Settings, this is only the answer to "what am I on?".
    /// Reads Free until the first answer lands, which is the honest thing
    /// to show while we genuinely don't know yet.
    private var membershipRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                rowTitle("Membership")
                if store.isSubscribed {
                    // The one word on the page allowed to dress up: serif,
                    // at the row's usual size, with a gold sheen that keeps
                    // clear of the rose the rest of the card uses.
                    Text("Premium")
                        .font(.editorial(16, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(light: "B98A2E", dark: "D9B266"),
                                    Palette.honey,
                                    Color(light: "C7973D", dark: "E3BF78"),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                } else {
                    Text("Free")
                        .font(.display(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    /// Presets and the person's own words on one line; nil when empty so
    /// the row shows its placeholder in rose.
    private func answer(_ labels: [String], custom: String) -> String? {
        let words = ProfileAnswers.joined(labels, custom: custom)
        return words.isEmpty ? nil : words.joined(separator: ", ")
    }

    private var nameRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                rowTitle("Name")
                TextField("Your name", text: $name)
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func choiceRow(
        title: String,
        value: String?,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    rowTitle(title)
                    Text(value ?? placeholder)
                        .font(.display(15, weight: .semibold))
                        .foregroundStyle(value == nil ? Palette.roseDeep : Palette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowTitle(_ text: String) -> some View {
        Text(text)
            .font(.display(11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkSoft)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Settings")
            VStack(spacing: 0) {
                subscriptionRow
                hapticsRow
                divider
                introRow
                divider
                resetRow
            }
            .softCard(padding: 8)
        }
    }

    /// Only while there's something to sell. Once they're subscribed there
    /// is nothing to manage here, and the About you card already says where
    /// they stand, so the row steps out rather than sit there inert.
    @ViewBuilder
    private var subscriptionRow: some View {
        if !store.isSubscribed {
            Button {
                Haptics.tap()
                PaywallCenter.shared.request(.chosen)
            } label: {
                HStack(spacing: 12) {
                    Text("Unlock premium")
                        .font(.display(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            divider
        }
    }

    private var hapticsRow: some View {
        HStack(spacing: 12) {
            Text("Haptics")
                .font(.display(15, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            Toggle("Haptics", isOn: $haptics)
                .labelsHidden()
                .tint(Palette.rose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Flips the root back to the intro. Answers stay; it plays from the top.
    private var introRow: some View {
        Button {
            Haptics.tap()
            didOnboard = false
        } label: {
            HStack(spacing: 12) {
                Text("See the onboarding again")
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var resetRow: some View {
        Button {
            Haptics.tap()
            confirmingReset = true
        } label: {
            HStack(spacing: 12) {
                Text("Start fresh")
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.roseDeep)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(meals.isEmpty && energyChecks.isEmpty)
        .opacity(meals.isEmpty && energyChecks.isEmpty ? 0.5 : 1)
    }

    private func reset() {
        for meal in meals { modelContext.delete(meal) }
        for check in energyChecks { modelContext.delete(check) }
        // Same deferred save as every other delete path: autosave can lag,
        // and a "start fresh" that never hit disk came back on relaunch.
        DispatchQueue.main.async { try? modelContext.save() }
        Haptics.success()
    }

    // MARK: - Footer

    /// Read from the bundle, so the row always says what the build says.
    private var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] ?? info?["CFBundleName"]) as? String ?? ""
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }

    /// The foot of the page: the health note first, then a quiet colophon
    /// of name and version in the secondary grey, feedback as an outlined
    /// capsule so it still reads as a button without a fill. Both sit on
    /// the same small inset, so they read as one block rather than two.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HealthDisclaimer()
            colophon
        }
        .padding(.horizontal, 4)
        .bottomCard(isPresented: $showSupport) {
            SupportCard()
        }
    }

    private var colophon: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.display(13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                Text(versionLine)
                    .font(.display(12, weight: .medium))
                    .foregroundStyle(Palette.inkSoft.opacity(0.75))
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                showSupport = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Support")
                        .font(.display(13, weight: .semibold))
                }
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Palette.card.opacity(0.7))
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                )
            }
            .buttonStyle(BounceStyle())
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// Screenshot hooks: "-uiseedyou" fills the page with a name, answers and
    /// three recipe-maker plates; "-uiyousheet goal|diet|avoid|builder|support|
    /// paywall" opens one of the answer sheets, or the paywall. Each fires
    /// once per process, so a
    /// launch left running with the flag never replays them on a later visit.
    private static var didApplyDebugArguments = false

    private func applyDebugLaunchArguments() {
        guard !Self.didApplyDebugArguments else { return }
        Self.didApplyDebugArguments = true
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uiyousheet"), index + 1 < arguments.count {
            // A beat later, like a tap: the card reads its item on change,
            // and a change in the same pass as first appearance is missed.
            let which = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if which == "builder" { showBuilder = true }
                else if which == "support" { showSupport = true }
                else if which == "paywall" { PaywallCenter.shared.request(.chosen) }
                else if which == "paywall-finished" { PaywallCenter.shared.request(.loopFinished) }
                else if which == "paywall-blocked" { PaywallCenter.shared.request(.blocked) }
                else { activeChoice = YouChoice(rawValue: which) }
            }
        }
        guard arguments.contains("-uiseedyou") else { return }
        name = "Maya"
        goalsRaw = Goal.encode([.steady, .cravings])
        dietRaw = Diet.vegetarian.rawValue
        avoidsRaw = Avoid.encode([.nuts, .sesame])
        avoidCustom = "Cilantro, Mushrooms"
        guard recipes.isEmpty else { return }
        for (offset, id) in ["avotoast", "yogurtbowl", "hummusplate"].enumerated() {
            guard let combo = KitchenLibrary.combos.first(where: { $0.id == id }) else { continue }
            modelContext.insert(Meal(
                name: combo.name,
                emoji: combo.emoji,
                date: .now.addingTimeInterval(Double(-offset) * 86_400 * 2),
                context: .pantry,
                compounds: KitchenLibrary.compounds(of: combo),
                boosts: combo.needs.compactMap { KitchenLibrary.ingredient($0)?.name }
            ))
        }
    }
    #endif
}

// MARK: - Support

/// One address for anything: a problem, an idea, a kind word. The address
/// is selectable and copies in a tap, so it works the same whether mail
/// lives on the phone or somewhere else.
private struct SupportCard: View {
    @Environment(\.dismissCard) private var dismiss
    @State private var copied = false

    private let address = "satisfed.app@gmail.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("We're here")
                        .font(.editorial(22, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Any problem or feedback, email us and a person will write back.")
                        .font(.display(13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
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
            .padding(.top, 22)

            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.roseDeep)
                Text(address)
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    Haptics.soft()
                    UIPasteboard.general.string = address
                    withAnimation(.spring(duration: 0.3)) { copied = true }
                    // A short confirmation, then back to a button: a chip
                    // that stays lit reads as switched on.
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(.easeOut(duration: 0.25)) { copied = false }
                    }
                } label: {
                    Text(copied ? "Copied" : "Copy")
                        .font(.display(13, weight: .semibold))
                        .foregroundStyle(copied ? Palette.roseDeep : Palette.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Palette.canvas)
                                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                        )
                        .contentTransition(.opacity)
                }
                .buttonStyle(BounceStyle())
                .accessibilityLabel(copied ? "Address copied" : "Copy the address")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
    }
}

// MARK: - Choice sheet

/// One question from onboarding, asked again: a list of answers with a
/// check on the chosen one. Single-choice sheets close themselves on a tap,
/// multi-choice ones wait for Done.
private struct ChoiceSheet<Choice: ProfileChoice>: View where Choice.AllCases: RandomAccessCollection {
    var title: String
    var subtitle: String? = nil
    var multi = false
    /// Two columns of short words instead of one list.
    var grid = false
    @Binding var selection: Set<Choice>
    /// The "in your own words" line under the presets, when the question has one.
    var custom: Binding<String>? = nil
    /// True when that line can hold several items, each shown as a chip.
    var customTakesSeveral = false
    @Environment(\.dismissCard) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.editorial(22, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.display(13, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.roseDeep)
            }
            .padding(.top, 22)

            VStack(spacing: 8) {
                if grid {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(Array(Choice.allCases)) { option in
                            ChoiceRow(label: option.label, isOn: selection.contains(option), compact: true) {
                                choose(option)
                            }
                        }
                    }
                } else {
                    ForEach(Array(Choice.allCases)) { option in
                        ChoiceRow(label: option.label, isOn: selection.contains(option)) {
                            choose(option)
                        }
                    }
                }
                if let custom {
                    if customTakesSeveral {
                        OwnAnswersField(text: custom)
                    } else {
                        CustomAnswerField(text: custom)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }

    private func choose(_ option: Choice) {
        if multi {
            if selection.contains(option) { selection.remove(option) } else { selection.insert(option) }
        } else {
            selection = [option]
            if custom == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { dismiss() }
            }
        }
    }
}
