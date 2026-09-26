//
//  ProgressTabView.swift
//  Shiphaton App
//
//  Progress: what has actually been happening. The week, the hunger
//  window, which builders showed up, and the recent history underneath,
//  which opens to the full log on a tap. Rings,
//  bars and dots carry it; captions only name what a panel found, never
//  explain it. No streaks, no scores, no numbers.
//

import SwiftUI
import SwiftData

struct ProgressTabView: View {
    @Environment(\.layout) private var layout
    @Query(sort: \Meal.date, order: .reverse) private var allMeals: [Meal]

    /// What was eaten and logged: snapped, typed, or picked from a craving.
    /// Plates built in the recipe maker are the recipe book on the You
    /// tab, not history; Home is the only place both show, and only for
    /// today.
    private var meals: [Meal] {
        allMeals.filter { $0.context != .pantry }
    }
    @Query(sort: \EnergyCheck.date, order: .reverse) private var energyChecks: [EnergyCheck]


    var body: some View {
        if meals.isEmpty {
            // Bare on the canvas and centred in the space above the bar: an
            // empty page, not a card announcing one.
            gatheringNote
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, layout.screenMargin)
                .padding(.bottom, layout.tabBarTop)
                .background(Palette.canvas)
        } else {
            content
        }
    }

    private var content: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: layout.sectionGap) {
                togetherSection
                weekSection
                hungerSection
                buildersSection
                if let energy = energySummary {
                    energySection(energy)
                }
                historySection
            }
            .id("bottom")
            .padding(.horizontal, layout.screenMargin)
            .padding(.top, 18)
            .padding(.bottom, layout.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.canvas)
        #if DEBUG
        // Screenshot hook, same as Home: "-uibottom" jumps to the end of the
        // page so the long sections can be eyeballed.
        .onAppear {
            guard ProcessInfo.processInfo.arguments.contains("-uibottom") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { scroll.scrollTo("bottom", anchor: .bottom) }
            }
        }
        #endif
        }
    }

    /// A single short read under a panel: names what the visual found and
    /// stops there.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.display(13, weight: .medium))
            .foregroundStyle(Palette.inkSoft)
            .padding(.horizontal, 4)
    }

    // MARK: - Windows of time

    private var recentMeals: [Meal] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return meals.filter { $0.date >= cutoff }
    }

    /// Hunger windows read better over a fortnight: two weeks of days
    /// smooths out the one odd Saturday.
    private var fortnightMeals: [Meal] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        return meals.filter { $0.date >= cutoff }
    }

    private var lastSevenDays: [Date] {
        (0..<7).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: .now))
        }
    }

    private func compounds(on day: Date) -> Set<Compound> {
        meals
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .reduce(into: []) { $0.formUnion($1.compounds) }
    }

    // MARK: - Empty state

    private var gatheringNote: some View {
        VStack(spacing: 12) {
            Text("🌱")
                .font(.system(size: 44))
            Text("Nothing here yet")
                .font(.editorial(19, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("Log a meal and this page fills itself in.")
                .font(.display(14, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Together

    /// The page opens on the one number this app is happy to say out loud:
    /// how many plates have been through here. A count of meals made
    /// better, never of anything on them. Bare on the canvas, one sentence,
    /// the count in rose so the eye lands on it first.
    private var togetherSection: some View {
        togetherLine
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("We've made \(plateCount) more satisfying together.")
    }

    private var plateCount: String {
        meals.count == 1 ? "1 meal" : "\(meals.count) meals"
    }

    private var togetherLine: Text {
        let piece = { (text: String, color: Color) in
            Text(text)
                .font(.editorial(28, weight: .semibold))
                .foregroundStyle(color)
        }
        return piece("We've made ", Palette.ink)
            + piece(plateCount, Palette.roseDeep)
            + piece(" more satisfying together.", Palette.ink)
    }

    // MARK: - The week

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your week")
            HStack(spacing: 0) {
                ForEach(lastSevenDays, id: \.self) { day in
                    VStack(spacing: 8) {
                        TrioRing(compounds: compounds(on: day), size: 32, lineWidth: 4, pastelTrack: true)
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.display(11, weight: .semibold))
                            .foregroundStyle(
                                Calendar.current.isDateInToday(day) ? Palette.roseDeep : Palette.inkSoft
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .softCard(padding: 16)
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Compound.allCases) { compound in
                HStack(spacing: 5) {
                    Circle()
                        .fill(compound.color)
                        .frame(width: 7, height: 7)
                    Text(compound.label)
                        .font(.display(12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Hunger windows

    private var hungerCounts: [(part: Daypart, count: Int)] {
        let grouped = Dictionary(grouping: fortnightMeals) { Daypart(from: $0.date) }
        return Daypart.allCases.map { ($0, grouped[$0]?.count ?? 0) }
    }

    private var busiestPart: Daypart? {
        hungerCounts.max { $0.count < $1.count }.flatMap { $0.count > 0 ? $0.part : nil }
    }

    /// Relative bars, never counts. The tallest window is the hungry one and
    /// the rest are read against it, which is the only comparison that
    /// matters here.
    private var hungerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "When hunger lands")
            VStack(alignment: .leading, spacing: 16) {
                let peak = max(1, hungerCounts.map(\.count).max() ?? 1)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(hungerCounts, id: \.part) { entry in
                        hungerBar(entry.part, share: Double(entry.count) / Double(peak))
                    }
                }
            }
            .softCard(padding: 18)
            if let busiest = busiestPart {
                caption("\(busiest.emoji) Your hungry window.")
            }
        }
    }

    private func hungerBar(_ part: Daypart, share: Double) -> some View {
        let isPeak = part == busiestPart
        return VStack(spacing: 8) {
            // Every window keeps a visible stub, so an empty one reads as
            // "quiet" rather than as missing data.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPeak ? AnyShapeStyle(Palette.roseGradient) : AnyShapeStyle(Palette.roseTint))
                .frame(height: 14 + 62 * share)
            Text(part.emoji)
                .font(.system(size: 15))
            Text(part.label)
                .font(.display(11, weight: .semibold))
                .foregroundStyle(isPeak ? Palette.roseDeep : Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: share)
    }

    // MARK: - Builders

    private func days(with compound: Compound) -> [Bool] {
        lastSevenDays.map { compounds(on: $0).contains(compound) }
    }

    /// A dot per day per builder: presence, at a glance, with the reason it
    /// matters written right beside it.
    private var buildersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What showed up")
            VStack(spacing: 14) {
                ForEach(Compound.allCases) { compound in
                    builderRow(compound)
                }
            }
            .softCard(padding: 18)
            if let quiet = quietestCompound {
                caption("\(quiet.emoji) \(quiet.label) has been quiet.")
            }
        }
    }

    private func builderRow(_ compound: Compound) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(compound.color)
                .frame(width: 8, height: 8)
            Text(compound.label)
                .font(.display(14, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
            HStack(spacing: 7) {
                ForEach(Array(days(with: compound).enumerated()), id: \.offset) { _, present in
                    Circle()
                        .fill(present ? compound.color : compound.color.opacity(0.16))
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    private var quietestCompound: Compound? {
        let counts = Compound.allCases.map { compound in
            (compound, days(with: compound).filter { $0 }.count)
        }
        guard let least = counts.min(by: { $0.1 < $1.1 }),
              let most = counts.max(by: { $0.1 < $1.1 }),
              least.1 < most.1 else { return nil }
        return least.0
    }

    // MARK: - Energy

    private struct EnergySummary {
        let emoji: String
        let title: String
    }

    /// One honest read on the check-ins, or nothing. Never a chart of moods.
    private var energySummary: EnergySummary? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recent = energyChecks.filter { $0.date >= cutoff }
        guard recent.count >= 3 else { return nil }

        let lows = recent.filter { $0.level == .low || $0.level == .meh }
        if lows.count * 2 >= recent.count {
            let grouped = Dictionary(grouping: lows) { Daypart(from: $0.date) }
            if let dip = grouped.max(by: { $0.value.count < $1.value.count }), dip.value.count >= 2 {
                return EnergySummary(emoji: dip.key.emoji, title: "Energy dips in the \(dip.key.label.lowercased())")
            }
            return EnergySummary(emoji: "🫠", title: "A flatter week")
        }
        return EnergySummary(emoji: "😌", title: "Energy is holding up")
    }

    private func energySection(_ summary: EnergySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Energy")
            HStack(spacing: 14) {
                EmojiTile(emoji: summary.emoji, size: 46, background: Palette.mist)
                Text(summary.title)
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            .softCard(padding: 16)
        }
    }

    // MARK: - History

    /// A month of days, then the day you picked. Nothing else is on screen,
    /// so the page stays the same length whether you have logged a week or
    /// a year. The calendar itself is shared with the You tab.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "History")
            MealCalendar(meals: meals, emptyText: "Nothing logged on this day.")
        }
    }
}
