//
//  Suggestions.swift
//  Shiphaton App
//
//  The cards in the "goes great with" deck and where they come from.
//
//  The engine calls the AI swipe-builder bot for real, tailored cards.
//  There is no stand-in deck any more: when the call can't be made (the
//  free round is spent, the network is out, the AI hiccuped) the engine
//  says so and the deck shows the person what happened and what to do
//  next, rather than dealing library cards that pretend to be an answer.
//

import Foundation

/// One card: an easy add, which builder it is mainly for, and a warm line
/// on why it fits.
struct Suggestion: Identifiable, Hashable {
    let boost: Boost
    /// The builder this card is "for". Drives its accent and the order
    /// cards are dealt in.
    let focus: Compound
    /// One short sentence, AI-written.
    let reason: String

    var id: String { boost.id }
}

enum SuggestionEngine {

    /// Deals a deck for the given craving/plate. Returns the resolved base
    /// builders (only meaningful on the first deck, when `accepted` and
    /// `rejected` are both empty) alongside the cards. Throws
    /// `AIError.paywallRequired` when the gate refused, or whatever the
    /// network raised; callers turn either into a card of its own.
    static func dealDeck(
        craving: String,
        food: Food?,
        base: Set<Compound>,
        accepted: [String],
        rejected: [String],
        note: String,
        profile: String
    ) async throws -> (base: Set<Compound>, cards: [Suggestion]) {
        let result = try await ComboAIClient.swipeDeck(
            craving: craving, accepted: accepted, rejected: rejected, note: note, profile: profile
        )
        let isFirstDeck = accepted.isEmpty && rejected.isEmpty
        let resolvedBase = isFirstDeck
            ? base.union(result.baseCompounds.compactMap { Compound(aiValue: $0) })
            : base
        // The AI is told the diet and the avoided foods in words and keeps to
        // them; this is the net under it, so a card that slips through
        // on a technicality never reaches the deck.
        let cards = DietaryFilter.keep(result.cards, name: \.item).map { card -> Suggestion in
            let adds = Set(card.compounds.compactMap { Compound(aiValue: $0) })
            let focus = Compound.allCases.first { !resolvedBase.contains($0) && adds.contains($0) }
                ?? adds.first ?? .protein
            return Suggestion(boost: Boost(card.item, card.emoji, adds: adds), focus: focus, reason: card.why)
        }
        return (resolvedBase, cards)
    }

    /// The teaching-moment summary once a swipe session wraps up. `nil`
    /// when there's nothing to celebrate yet or the call fails, the deck's
    /// default finished copy covers that case.
    static func summary(
        craving: String,
        accepted: [String],
        compoundsCovered: Set<Compound>,
        note: String,
        profile: String
    ) async -> SwipeSummaryResult? {
        guard !accepted.isEmpty else { return nil }
        return try? await ComboAIClient.swipeSummary(
            craving: craving, accepted: accepted,
            compoundsCovered: compoundsCovered.map(\.aiValue), note: note, profile: profile
        )
    }

    /// The same card, now dealt for a different builder because the one it
    /// was originally for is already on the plate. The reason stays put,
    /// it already describes how the item joins the snack regardless of
    /// which builder heading it's filed under.
    static func refocused(_ card: Suggestion, to focus: Compound) -> Suggestion {
        Suggestion(boost: card.boost, focus: focus, reason: card.reason)
    }
}
