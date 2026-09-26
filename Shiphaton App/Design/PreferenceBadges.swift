//
//  PreferenceBadges.swift
//  Shiphaton App
//
//  The small tags that ride along with suggestions, so it's visible that
//  what's being dealt keeps to how the person eats: "Vegetarian", "No
//  nuts". Read live from the profile, so an edit on the You tab shows up
//  the next time a deck is dealt. Both views render nothing at all when
//  there's nothing to say.
//
//  Colours stay off the trio's three: rose, sage and gold mean protein,
//  fibre and fats everywhere else, so a diet tag in sage next to a fibre
//  tag would read as one more builder.
//

import SwiftUI

// MARK: - Reading the profile

/// What's worth showing as a badge, out of everything saved.
struct PreferenceSnapshot {
    var diet: Diet?
    var dietOwnWords: String
    var avoids: Set<Avoid>
    var avoidOwnWords: String

    /// The one tag a suggestion card carries: the diet preset, or the
    /// person's own short phrase when they typed one instead.
    var dietTag: (icon: String, label: String)? {
        if let badge = diet?.badge { return badge }
        let own = dietOwnWords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !own.isEmpty, own.count <= 18 else { return nil }
        return ("fork.knife", own.capitalizedFirst)
    }

    /// "No …" chips, presets first, then each own item that's short
    /// enough to wear as a tag.
    var avoidLabels: [String] {
        var labels = Avoid.allCases.filter(avoids.contains).map(\.badgeLabel)
        for own in ProfileAnswers.list(avoidOwnWords) where own.count <= 16 {
            labels.append("No \(own.lowercased())")
        }
        return labels
    }

    var isEmpty: Bool { dietTag == nil && avoidLabels.isEmpty }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - One tag

/// The diet on its own, sized to sit in a card's corner opposite the
/// builder tag: same uppercase, same tracking, a cool slate so it never
/// reads as a fourth builder.
struct DietTag: View {
    @AppStorage(ProfileKey.diet) private var dietRaw = ""
    @AppStorage(ProfileKey.dietCustom) private var dietOwnWords = ""

    var body: some View {
        let snapshot = PreferenceSnapshot(diet: Diet(rawValue: dietRaw), dietOwnWords: dietOwnWords, avoids: [], avoidOwnWords: "")
        if let tag = snapshot.dietTag {
            HStack(spacing: 4) {
                Image(systemName: tag.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(tag.label)
                    .font(.display(11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.slate)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Palette.slateTint))
            .accessibilityLabel("Keeps to \(tag.label)")
        }
    }
}

// MARK: - The row

/// Diet first, then the "No …" chips, on one line that scrolls sideways
/// if someone has a long list. Hidden entirely when the profile is empty.
struct PreferenceBadges: View {
    var alignment: HorizontalAlignment = .leading

    @AppStorage(ProfileKey.diet) private var dietRaw = ""
    @AppStorage(ProfileKey.dietCustom) private var dietOwnWords = ""
    @AppStorage(ProfileKey.avoids) private var avoidsRaw = ""
    @AppStorage(ProfileKey.avoidCustom) private var avoidOwnWords = ""

    private var snapshot: PreferenceSnapshot {
        PreferenceSnapshot(
            diet: Diet(rawValue: dietRaw), dietOwnWords: dietOwnWords,
            avoids: Avoid.decode(avoidsRaw), avoidOwnWords: avoidOwnWords
        )
    }

    var body: some View {
        let snapshot = snapshot
        if !snapshot.isEmpty {
            // A horizontal scroll view sizes to its content, so it can't
            // centre a short row. Lay the row out plainly when it fits and
            // only fall back to scrolling when the list is long.
            ViewThatFits(in: .horizontal) {
                row(snapshot)
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                ScrollView(.horizontal) {
                    row(snapshot)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ snapshot: PreferenceSnapshot) -> some View {
        HStack(spacing: 6) {
            if let tag = snapshot.dietTag {
                chip(icon: tag.icon, text: tag.label, color: Palette.slate, fill: Palette.slateTint, stroke: .clear)
            }
            ForEach(snapshot.avoidLabels, id: \.self) { label in
                chip(icon: nil, text: label, color: Palette.inkSoft, fill: Palette.card, stroke: Palette.hairline)
            }
        }
    }

    private func chip(icon: String?, text: String, color: Color, fill: Color, stroke: Color) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.display(12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(fill)
                .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        )
    }
}
