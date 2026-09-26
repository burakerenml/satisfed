//
//  MealCalendar.swift
//  Shiphaton App
//
//  A month of days with a dot on each one that has something, then the
//  day you picked as its own cards. History is browsed by month rather
//  than scrolled: a day a month back is a tap away, not a hundred cards
//  away. Shared by Progress (every logged meal) and You (the plates built
//  from what was on hand), so the two read as one calendar.
//

import SwiftUI

struct MealCalendar: View {
    /// Whatever the owner wants on the calendar. Filtering is theirs.
    var meals: [Meal]
    /// The line under a day with nothing on it.
    var emptyText = "Nothing on this day."
    /// Off where every card shares one context anyway.
    var showsContext = true
    /// Supplied where a card can be swiped away.
    var onRemove: ((Meal) -> Void)? = nil

    @State private var visibleMonth = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            monthCard
            selectedDaySection
        }
    }

    private func meals(on day: Date) -> [Meal] {
        meals
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    // MARK: Month grid

    private var calendar: Calendar { Calendar.current }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
    }

    private var thisMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
    }

    /// The month laid out in weeks: leading blanks so the first day lands
    /// under the right weekday, then every day of the month.
    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let days: [Date?] = range.compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 1, to: monthStart)
        }
        return Array(repeating: nil, count: leading) + days
    }

    /// Weekday initials, rotated to wherever the user's week starts.
    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + shift) % 7] }
    }

    private var monthCard: some View {
        VStack(spacing: 14) {
            monthHeader
            HStack(spacing: 0) {
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.display(11, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .softCard(padding: 16)
    }

    private var monthHeader: some View {
        HStack {
            monthArrow("chevron.left", enabled: true) { step(-1) }
            Spacer(minLength: 0)
            Text(monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.editorial(17, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            monthArrow("chevron.right", enabled: monthStart < thisMonthStart) { step(1) }
        }
    }

    private func monthArrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Palette.roseDeep : Palette.inkSoft.opacity(0.3))
                .frame(width: 34, height: 34)
                .background(Circle().fill(enabled ? Palette.blush : Color.clear))
        }
        .disabled(!enabled)
        .buttonStyle(BounceStyle())
    }

    private func step(_ months: Int) {
        Haptics.tap()
        guard let next = calendar.date(byAdding: .month, value: months, to: monthStart) else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { visibleMonth = next }
    }

    /// Days carry a dot, not a ring. A day holds several meals and each one
    /// has its own trio, so a single ring on the day would be answering a
    /// question nobody asked. The dot says "there is something here"; the
    /// cards below say what.
    private func dayCell(_ day: Date) -> some View {
        let logged = !meals(on: day).isEmpty
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date.now
        return Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { selectedDay = day }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Palette.blush)
                            .frame(width: 32, height: 32)
                    }
                    Text("\(calendar.component(.day, from: day))")
                        .font(.display(13, weight: isSelected || isToday ? .bold : .medium))
                        .foregroundStyle(dayNumberColor(isSelected: isSelected, isToday: isToday, isFuture: isFuture))
                }
                .frame(width: 32, height: 32)
                Circle()
                    .fill(logged ? Palette.roseDeep : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .disabled(isFuture)
        .buttonStyle(BounceStyle())
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(logged ? "Something here" : "Nothing here")
    }

    private func dayNumberColor(isSelected: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isFuture { return Palette.inkSoft.opacity(0.28) }
        if isSelected || isToday { return Palette.roseDeep }
        return Palette.ink
    }

    // MARK: The chosen day

    /// Same shape as Home's Today: a heading, then that day's meals as their
    /// own cards. The day itself carries no ring; the meals do.
    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dayLabel(selectedDay))
                .font(.editorial(17, weight: .semibold))
                .foregroundStyle(calendar.isDateInToday(selectedDay) ? Palette.roseDeep : Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            let dayMeals = meals(on: selectedDay)
            if dayMeals.isEmpty {
                Text(emptyText)
                    .font(.display(14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCard(padding: 16)
            } else {
                VStack(spacing: 12) {
                    ForEach(dayMeals) { meal in
                        MealCard(
                            meal: meal,
                            showsContext: showsContext,
                            onRemove: onRemove.map { remove in { remove(meal) } }
                        )
                    }
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: selectedDay)
    }

    private func dayLabel(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
