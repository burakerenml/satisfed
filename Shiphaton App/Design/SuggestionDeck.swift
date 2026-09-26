//
//  SuggestionDeck.swift
//  Shiphaton App
//
//  The "goes great with" deck. One easy add per card. Swipe right to put
//  it on the plate, left to pass, the way dating apps do it: right is yes.
//  Three cards deep, the top one follows the finger with a tilt and
//  stamps, and a liquid-glass row under the stack mirrors the gestures for
//  anyone who would rather tap. Nothing is ever taken off the plate; a
//  left swipe just moves on.
//

import SwiftUI

// MARK: - Model

/// Why there are no cards to swipe, when there aren't. Each one is drawn
/// as a card of its own in the stack, so the deck never sits empty and
/// never deals stand-ins.
enum DeckBlocker: Equatable {
    /// The free round is spent and nothing has been bought.
    case locked
    /// The cards couldn't be fetched: the network, or the AI itself.
    case failed(message: String, offline: Bool)
}

@Observable
final class SuggestionDeckModel {
    struct Decision: Hashable {
        let suggestion: Suggestion
        let added: Bool
    }

    /// Set instead of cards when none could be dealt. Cleared by `load`.
    var blocker: DeckBlocker?

    /// Everything the engine dealt, in its order.
    private(set) var dealt: [Suggestion] = []
    /// Builders the plate had before any adds.
    private(set) var base: Set<Compound> = []
    private(set) var decisions: [Decision] = []
    var isLoading = false
    /// How many decks the AI has dealt this session. Starts at 1 once the
    /// first deck lands.
    private(set) var decksDealt = 0
    /// The stop rule: two decks normally. A swiper who has said no to
    /// everything so far keeps getting fresh directions (up to five decks,
    /// each dealt with a bolder change of direction) rather than a dead end.
    var canDealMore: Bool { decksDealt < (chosen.isEmpty ? 5 : 2) }
    /// The AI's end-of-session teaching moment, once fetched.
    var summary: SwipeSummaryResult?
    var isSummaryLoading = false

    var chosen: [Suggestion] { decisions.filter(\.added).map(\.suggestion) }
    var canUndo: Bool { !decisions.isEmpty }
    var top: Suggestion? { remaining.first }
    var isFinished: Bool { remaining.isEmpty && !isLoading }

    /// What the plate covers with the adds so far.
    var covered: Set<Compound> {
        chosen.reduce(into: base) { $0.formUnion($1.boost.adds) }
    }

    /// The live deck, derived rather than stored: undecided cards that still
    /// bring something the plate is missing, walked builder by builder in
    /// trio order. Add a protein card and the other protein cards fall away
    /// so the deck moves on to fibre; a card that also brings fibre stays
    /// and is re-dealt for fibre. Undo simply re-derives.
    var remaining: [Suggestion] { remaining(after: decisions) }

    /// The deck as it will look once `card` is added: what the stack behind
    /// a card being dragged right previews, so nothing changes on commit.
    func remaining(afterAdding card: Suggestion) -> [Suggestion] {
        remaining(after: decisions + [Decision(suggestion: card, added: true)])
    }

    private func remaining(after decisions: [Decision]) -> [Suggestion] {
        let decided = Set(decisions.map(\.suggestion.id))
        let covered = decisions.filter(\.added).reduce(into: base) { $0.formUnion($1.suggestion.boost.adds) }
        var out: [Suggestion] = []
        for compound in Compound.allCases where !covered.contains(compound) {
            for card in dealt
            where !decided.contains(card.id)
                && card.boost.adds.contains(compound)
                && !out.contains(where: { $0.id == card.id }) {
                out.append(card.focus == compound ? card : SuggestionEngine.refocused(card, to: compound))
            }
        }
        return out
    }

    func load(_ cards: [Suggestion], base: Set<Compound>) {
        dealt = cards
        self.base = base
        decisions = []
        decksDealt = 1
        summary = nil
        isSummaryLoading = false
        blocker = nil
    }

    /// A follow-up deck once the first one's exhausted but the plate still
    /// isn't complete. Cards join `dealt` without touching decisions, so
    /// nothing already swiped moves.
    func appendDealt(_ cards: [Suggestion]) {
        dealt.append(contentsOf: cards)
        decksDealt += 1
    }

    func reset() { load([], base: []) }

    @discardableResult
    func decide(_ added: Bool) -> Suggestion? {
        guard let card = top else { return nil }
        decisions.append(Decision(suggestion: card, added: added))
        return card
    }

    /// A typed-in add-on, bypassing the deck entirely: the person names it
    /// and picks which builders it brings themselves. Lands in `decisions`
    /// exactly like a swiped-right card, so it counts toward `covered` and
    /// shows up in `chosen` right alongside the ones that came from cards.
    @discardableResult
    func addCustom(name: String, adds: Set<Compound>) -> Suggestion {
        let focus = Compound.allCases.first(where: adds.contains) ?? .protein
        let suggestion = Suggestion(boost: Boost(name, "✨", adds: adds), focus: focus, reason: "Added by you.")
        decisions.append(Decision(suggestion: suggestion, added: true))
        return suggestion
    }

    @discardableResult
    func undo() -> Decision? {
        // The AI's teaching-moment summary describes a specific accepted
        // set; once undo changes that set, the cached summary is stale
        // (it can still name an item that's no longer on the plate), so
        // drop it and let the caller re-fetch for the new state.
        summary = nil
        isSummaryLoading = false
        return decisions.popLast()
    }
}

// MARK: - Deck

struct SuggestionDeck: View {
    var model: SuggestionDeckModel
    /// Fired once a card has flown off and the model has moved on.
    var onDecision: (Suggestion, Bool) -> Void
    /// Fired after a decision is undone, so the caller can react to the
    /// plate no longer matching whatever it last fetched (the AI summary
    /// in particular, since `model.undo()` already drops the stale one).
    var onUndo: (() -> Void)? = nil
    /// The "Try again" on a failed deal.
    var onRetry: (() -> Void)? = nil
    /// The "Unlock" on a locked deck.
    var onUnlock: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Owned state rather than `@GestureState`, so the card hands off from
    /// finger to spring in one motion instead of snapping to zero first.
    @State private var drag: CGSize = .zero
    @State private var isDragging = false
    @State private var isFlying = false
    /// The cards behind rise into their promoted spots in the same motion
    /// as the top card flying off, so the stack cascades forward as one
    /// continuous move instead of popping into place afterwards.
    @State private var promoted = false
    /// The card currently flying off, kept alive here independently of the
    /// model: `model.decide` fires the instant the flight starts (not once
    /// it finishes), so anything outside the deck that reflects the pick —
    /// the plate's trio ring, its name, its builder chips — animates in the
    /// very same motion as the card leaving, rather than visibly catching
    /// up once it's already gone. This just keeps that one card rendering,
    /// and draggable, through its exit while the model has already moved on.
    @State private var flying: Suggestion?
    /// The card on its way back after an undo, and the side it returns
    /// from. Cards pruned by an add come back at the same time; they enter
    /// silently behind it.
    @State private var undoing: (id: String, side: CGFloat)?
    @State private var hinted = false
    @State private var showManualAdd = false
    /// Where each tossed card ended up, kept by id until its removal has
    /// fully played out. SwiftUI keeps a removed view around for the length
    /// of its transition and keeps re-reading its modifiers, so if the
    /// departed card read the shared `drag` after the reset it would snap
    /// back on screen for a beat before vanishing.
    @State private var departed: [String: CGSize] = [:]

    private let threshold: CGFloat = 110
    private let flyDistance: CGFloat = 720
    private let depth = 3

    /// -1 fully skipping … 1 fully adding.
    private var progress: CGFloat { max(-1, min(1, drag.width / threshold)) }

    var body: some View {
        VStack(spacing: 30) {
            stack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // No discs under a card that can't be swiped: they would only
            // promise a gesture the card doesn't answer.
            if model.blocker == nil {
                actions
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: model.blocker)
        .onChange(of: model.top?.id, initial: true) { _, id in
            guard id != nil, !hinted else { return }
            hinted = true
            nudge()
        }
    }

    // MARK: Stack

    /// The cards behind the top one, as the deck will look once the top
    /// card goes where the finger is taking it. Right previews the deck
    /// after adding, so cards the add makes redundant are already gone;
    /// left simply shows the next card. Only meaningful before a decision
    /// is made — once a card is `flying`, the model already reflects it.
    private var behind: [Suggestion] {
        guard let top = model.top else { return [] }
        if progress > 0 { return model.remaining(afterAdding: top) }
        return Array(model.remaining.dropFirst())
    }

    /// What the finished card lists, including the card on its way in.
    private var projectedChosen: [Suggestion] {
        if flying == nil, let top = model.top, progress > 0 { return model.chosen + [top] }
        return model.chosen
    }

    /// Whether the deck is about to run out — reads the model directly
    /// while a card is flying, since `behind` previews the pre-decision
    /// state and the decision has, by then, already been made.
    private var isEnding: Bool {
        flying == nil ? behind.isEmpty : model.remaining.isEmpty
    }

    private var stackCards: [Suggestion] {
        if let flying {
            // The model has already moved on to the next card; splice the
            // departing one back in at the front so it keeps rendering,
            // and stays draggable, through the rest of its exit.
            let rest = model.remaining.filter { $0.id != flying.id }
            return [flying] + rest.prefix(depth - 1)
        }
        guard let top = model.top else { return [] }
        return [top] + behind.prefix(depth - 1)
    }

    private var stack: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let cards = stackCards
            ZStack {
                if model.isLoading {
                    loadingCard
                        .transition(.opacity)
                } else if let blocker = model.blocker {
                    BlockedCard(blocker: blocker, compact: height < 300, onRetry: onRetry, onUnlock: onUnlock)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if isEnding {
                    // The finished card is the next thing, so it waits in
                    // the stack like any card and is simply there on commit.
                    FinishedCard(
                        chosen: projectedChosen, compact: height < 300,
                        summary: model.summary, isSummaryLoading: model.isSummaryLoading
                    )
                        .scaleEffect(scale(at: cards.count))
                        .offset(y: lift(at: cards.count))
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }

                ForEach(Array(cards.enumerated()).reversed(), id: \.element.id) { index, card in
                    let isTop = index == 0
                    SuggestionCard(suggestion: card, progress: isTop ? progress : 0, height: height)
                        .scaleEffect(scale(at: index))
                        .offset(y: lift(at: index))
                        .offset(departed[card.id] ?? (isTop ? drag : .zero))
                        .rotationEffect(isTop ? tilt : .zero, anchor: .bottom)
                        .zIndex(Double(depth - index))
                        .gesture(swipe, including: isTop ? .gesture : .none)
                        .transition(.asymmetric(insertion: entrance(for: card), removal: .identity))
                        .accessibilityElement(children: .combine)
                        .accessibilityAction(named: "Add it") { if isTop { fly(added: true) } }
                        .accessibilityAction(named: "Skip") { if isTop { fly(added: false) } }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Room for the cards behind to peek above the top one.
        .padding(.top, 22)
    }

    /// Three arrivals animate: the first deal rises in, an undone card
    /// slides back from the side it left, and a card newly revealed at the
    /// back of the stack — once a decision frees up the slot behind it —
    /// fades and grows in rather than popping, so it reads as part of the
    /// same motion as the card ahead of it settling in.
    private func entrance(for card: Suggestion) -> AnyTransition {
        if let undoing {
            return card.id == undoing.id ? .offset(x: undoing.side) : .identity
        }
        if model.decisions.isEmpty {
            return .opacity.combined(with: .offset(y: 22)).combined(with: .scale(scale: 0.96))
        }
        return .opacity.combined(with: .scale(scale: 0.92))
    }

    /// Cards behind sit smaller and higher. They hold still under the
    /// finger; the deck only re-seats them, without animation, once the top
    /// card is on its way out.
    private func scale(at index: Int) -> CGFloat {
        let depthBehind = max(0, promoted ? index - 1 : index)
        return 1 - 0.06 * CGFloat(depthBehind)
    }

    private func lift(at index: Int) -> CGFloat {
        let depthBehind = max(0, promoted ? index - 1 : index)
        return -13 * CGFloat(depthBehind)
    }

    private var tilt: Angle {
        guard !reduceMotion else { return .zero }
        return .degrees(Double(max(-16, min(16, drag.width / 14))))
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Palette.rose)
            Text("Finding easy adds")
                .font(.display(14, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deckCard()
    }

    // MARK: Gesture

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !isFlying else { return }
                isDragging = true
                drag = CGSize(width: value.translation.width, height: value.translation.height * 0.55)
            }
            .onEnded { value in
                isDragging = false
                guard !isFlying else { return }
                // A flick finishes the gesture the finger started.
                let predicted = value.predictedEndTranslation.width
                let decisive = abs(predicted) > abs(drag.width) ? predicted : drag.width
                if decisive > threshold {
                    fly(added: true)
                } else if decisive < -threshold {
                    fly(added: false)
                } else {
                    withAnimation(.spring(duration: 0.45, bounce: 0.32)) { drag = .zero }
                }
            }
    }

    /// Toss the top card off the side it was decided on. `model.decide`
    /// fires right here, in the very same animation as the flight and the
    /// promotion of the cards behind it — not once the flight finishes —
    /// so the ring, the plate name and the builder chips all fill in
    /// alongside the card leaving instead of visibly catching up
    /// afterwards. `flying` keeps this one card rendering, independently
    /// of the model, for the rest of its exit.
    private func fly(added: Bool) {
        guard !isFlying, let card = model.top else { return }
        isFlying = true
        flying = card
        let direction: CGFloat = added ? 1 : -1
        let destination = CGSize(width: direction * flyDistance, height: drag.height * 1.3 - 36)
        withAnimation(.spring(duration: 0.42, bounce: 0.16), completionCriteria: .logicallyComplete) {
            drag = destination
            promoted = true
            model.decide(added)
        } completion: {
            land(card)
        }
        onDecision(card, added)
    }

    /// Pure bookkeeping once the flight has played out — and the ONLY
    /// thing that happens here, in a single silent step. The departed
    /// card is pinned exactly where it landed (so it can't snap back
    /// while SwiftUI finishes tearing it down) and dropped from `flying`
    /// in the very same instant; nothing here is a second, separately
    /// animated beat, since `promoted` already carried the surviving
    /// cards to exactly the scale and offset their new index now gives
    /// them. The pick itself already animated, back in `fly`.
    private func land(_ card: Suggestion) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            departed[card.id] = drag
            drag = .zero
            promoted = false
            flying = nil
        }
        isFlying = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            departed[card.id] = nil
        }
    }

    private func undo() {
        guard !isFlying, let last = model.decisions.last else { return }
        isFlying = true
        Haptics.soft()
        undoing = (last.suggestion.id, (last.added ? 1 : -1) * flyDistance)
        // A card brought back within its clean-up window must not stay
        // pinned where it was tossed.
        departed[last.suggestion.id] = nil
        withAnimation(.spring(duration: 0.55, bounce: 0.22), completionCriteria: .logicallyComplete) {
            model.undo()
        } completion: {
            undoing = nil
            isFlying = false
        }
        onUndo?()
    }

    /// A small lean to the right on the first deal, so the gesture teaches
    /// itself without a tutorial. Only ever scheduled once, but a quick
    /// swipe can still move the deck past the original card before this
    /// fires a second later — checked here so the hint never lands on a
    /// card the person has already moved past, which would just read as
    /// an unprompted, unwanted jump.
    private func nudge() {
        guard !reduceMotion, let id = model.top?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !isFlying, !isDragging, drag == .zero, model.top?.id == id else { return }
            withAnimation(.spring(duration: 0.55, bounce: 0.45)) { drag.width = 30 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard !isFlying, !isDragging, model.top?.id == id else { return }
                withAnimation(.spring(duration: 0.6, bounce: 0.3)) { drag = .zero }
            }
        }
    }

    // MARK: Actions

    /// Undo · skip · add, in one glass container so the discs share their
    /// liquid the way the tab bar's capsule and camera do.
    private var actions: some View {
        let hasCard = model.top != nil
        return GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                ActionDisc(
                    symbol: "arrow.uturn.backward", size: 46, icon: 15,
                    tint: Palette.card.opacity(0.55), color: Palette.inkSoft,
                    enabled: model.canUndo, label: "Bring back the last one",
                    pulseColor: Palette.inkSoft,
                    action: undo
                )
                ActionDisc(
                    symbol: "xmark", size: 64, icon: 24,
                    tint: Palette.card.opacity(0.55), color: Palette.inkSoft,
                    enabled: hasCard, label: "Skip",
                    pulseColor: Palette.inkSoft
                ) { fly(added: false) }
                ActionDisc(
                    symbol: "plus", size: 64, icon: 24,
                    tint: Palette.rose, color: .white,
                    enabled: hasCard, label: "Add it"
                ) { fly(added: true) }
                ActionDisc(
                    symbol: "square.and.pencil", size: 46, icon: 15,
                    tint: Palette.card.opacity(0.55), color: Palette.inkSoft,
                    enabled: true, label: "Add your own",
                    pulseColor: Palette.inkSoft
                ) { showManualAdd = true }
            }
        }
        .shadow(color: Color(hex: "2E3A54").opacity(0.08), radius: 16, y: 8)
        .bottomCard(isPresented: $showManualAdd) {
            ManualAddSheet { name, tags in
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    let suggestion = model.addCustom(name: name, adds: tags)
                    onDecision(suggestion, true)
                }
            }
        }
    }

}

// MARK: - Action disc

/// One disc in the deck's action row. It owns its own pulse count, so the
/// ring rides out from the disc that was actually tapped, and only when the
/// tap did something.
private struct ActionDisc: View {
    var symbol: String
    var size: CGFloat
    var icon: CGFloat
    var tint: Color
    var color: Color
    var enabled: Bool
    var label: String
    var pulseColor: Color = Palette.rose
    var action: () -> Void

    @State private var pulses = 0

    var body: some View {
        Button {
            guard enabled else { return }
            pulses += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: icon, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint).interactive(), in: Circle())
        .overlay(Circle().stroke(Palette.hairline.opacity(color == .white ? 0 : 0.7), lineWidth: 1))
        // On top of the glass, so the ring reads as leaving the disc.
        .pulse(Circle(), trigger: pulses, color: pulseColor)
        .opacity(enabled ? 1 : 0.38)
        .animation(.easeOut(duration: 0.22), value: enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Card

struct SuggestionCard: View {
    var suggestion: Suggestion
    /// -1 skipping … 1 adding. Drives the stamps and the wash.
    var progress: CGFloat = 0
    /// Height the deck has to give, so a mini and a Pro Max both get a
    /// proportioned card.
    var height: CGFloat = 400

    private var focus: Compound { suggestion.focus }
    private var adding: Double { Double(max(0, min(1, progress * 1.5))) }
    private var skipping: Double { Double(max(0, min(1, -progress * 1.5))) }
    private var compact: Bool { height < 300 }
    /// Builders this card adds beyond the one already named in the top-left
    /// badge, so a single-builder card doesn't repeat itself with a pill.
    private var extraAdds: Set<Compound> { suggestion.boost.adds.subtracting([focus]) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text(focus.label)
                        .font(.display(11, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(focus.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(focus.tint))
                    Spacer()
                    // The builder on the left, how they eat on the right:
                    // every card says it was dealt for this person.
                    DietTag()
                }

                Spacer(minLength: 12)

                Text(suggestion.boost.name)
                    .font(.editorial(compact ? 24 : 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                if !compact {
                    Text(suggestion.reason)
                        .font(.display(15, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 12)
                        .padding(.horizontal, 8)
                }

                Spacer(minLength: 12)

                if !extraAdds.isEmpty {
                    AddsPills(adds: extraAdds)
                }
            }
            .padding(compact ? 18 : 24)

            stamps
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deckCard(wash: wash, edge: edge)
        .accessibilityLabel("\(suggestion.boost.name). \(suggestion.reason)")
    }

    private var wash: Color {
        if adding > 0 { return Palette.rose.opacity(0.10 * adding) }
        return Palette.slate.opacity(0.10 * skipping)
    }

    private var edge: Color {
        if adding > 0 { return Palette.rose.opacity(0.9 * adding) }
        return Palette.slate.opacity(0.7 * skipping)
    }

    private var stamps: some View {
        ZStack {
            stamp("Add it", color: Palette.roseDeep, amount: adding)
                .rotationEffect(.degrees(-14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            stamp("Skip", color: Palette.slate, amount: skipping)
                .rotationEffect(.degrees(14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(22)
        .padding(.top, 36)
        .allowsHitTesting(false)
    }

    private func stamp(_ text: String, color: Color, amount: Double) -> some View {
        Text(text)
            .font(.display(22, weight: .heavy))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color, lineWidth: 3)
            )
            .opacity(amount)
            .scaleEffect(0.82 + 0.18 * amount)
    }
}

// MARK: - Finished

private struct FinishedCard: View {
    var chosen: [Suggestion]
    var compact: Bool
    /// The AI's teaching-moment writeup, once fetched. Falls back to the
    /// default copy below once it's clear none is coming.
    var summary: SwipeSummaryResult? = nil
    /// True while the writeup above is still in flight. The card waits for
    /// it rather than showing the fallback copy first and swapping it out
    /// a beat later — that swap read as a glitch, not a reveal.
    var isSummaryLoading = false

    @AppStorage(ProfileKey.name) private var name = ""

    var body: some View {
        Group {
            if isSummaryLoading {
                gathering
            } else {
                finished
            }
        }
        .padding(compact ? 18 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deckCard()
        .animation(.easeOut(duration: 0.3), value: isSummaryLoading)
    }

    /// Held while the plate's teaching moment is still being written, so
    /// nothing shows up half-true. Its own short beat, not a stand-in for
    /// the card underneath.
    private var gathering: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Palette.rose)
            Text("Bringing the plate together")
                .font(.display(14, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var finished: some View {
        VStack(spacing: 10) {
            Text(summary?.title ?? (chosen.isEmpty ? "Just as it is" : "That's the lot"))
                .font(.editorial(22, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(summary?.explanation ?? (chosen.isEmpty
                 ? "Logging it as it is. Still counts."
                 : "Here's what you're adding. Undo takes one back."))
                .font(.display(13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(3)
                .minimumScaleFactor(0.85)

            if !chosen.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(chosen) { suggestion in
                            chosenRow(suggestion)
                        }
                    }
                    .padding(.top, 4)
                }
                .scrollIndicators(.hidden)

                Text(celebrationLine)
                    .font(.display(12, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    private var celebrationLine: String {
        name.isEmpty
            ? "Nice one! That's more satisfying already."
            : "Nice one, \(name)! That's more satisfying already."
    }

    private func chosenRow(_ suggestion: Suggestion) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(suggestion.focus.color)
                .frame(width: 4)
                .padding(.vertical, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.boost.name)
                    .font(.display(14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                AddsPills(adds: suggestion.boost.adds)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.canvas)
        )
    }
}

// MARK: - Blocked

/// The card that stands in the stack when there are no cards to deal: the
/// free round is spent, the network is out, or the AI didn't answer. Says
/// what happened in one line and offers the one thing that fixes it.
private struct BlockedCard: View {
    var blocker: DeckBlocker
    var compact: Bool
    var onRetry: (() -> Void)?
    var onUnlock: (() -> Void)?

    private var symbol: String {
        switch blocker {
        case .locked: "lock.fill"
        case .failed(_, let offline): offline ? "wifi.slash" : "exclamationmark.bubble"
        }
    }

    private var color: Color {
        switch blocker {
        case .locked: Palette.rose
        case .failed(_, let offline): offline ? Palette.slate : Palette.honey
        }
    }

    private var tint: Color {
        switch blocker {
        case .locked: Palette.roseTint
        case .failed(_, let offline): offline ? Palette.slateTint : Palette.honeyTint
        }
    }

    private var title: String {
        switch blocker {
        case .locked: "Join satisfed Premium"
        case .failed(_, let offline): offline ? "You're offline" : "Couldn't deal the cards"
        }
    }

    private var line: String {
        switch blocker {
        case .locked:
            "Your free round is done. Join to keep the easy adds coming, every plate, every time."
        case .failed(let message, let offline):
            // The title already says offline; the line says what fixes it.
            offline ? "Connect to the internet and we'll deal the cards." : message
        }
    }

    private var buttonTitle: String {
        switch blocker {
        case .locked: "Join Premium"
        case .failed: "Try again"
        }
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            Spacer(minLength: 0)
            // The lock stands on its own; the trouble icons keep a soft disc
            // so a wifi glyph doesn't float unanchored.
            ZStack {
                if blocker != .locked {
                    Circle()
                        .fill(tint)
                        .frame(width: compact ? 52 : 64, height: compact ? 52 : 64)
                }
                Image(systemName: symbol)
                    .font(.system(size: blocker == .locked ? (compact ? 30 : 36) : (compact ? 20 : 24), weight: .semibold))
                    .foregroundStyle(color)
            }
            .padding(.bottom, blocker == .locked ? 4 : 0)
            Text(title)
                .font(.editorial(compact ? 20 : 22, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(line)
                .font(.display(compact ? 13 : 14, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 6)
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                switch blocker {
                case .locked: onUnlock?()
                case .failed: onRetry?()
                }
            } label: {
                Text(buttonTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(compact ? 18 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .deckCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Manual add

/// The "type it in" escape hatch next to the plus button: skips the cards
/// entirely, the person names their own add-on and taps which builders it
/// brings themselves.
private struct ManualAddSheet: View {
    var onAdd: (String, Set<Compound>) -> Void

    @Environment(\.dismissCard) private var dismiss
    @State private var name = ""
    @State private var tags: Set<Compound> = []
    @FocusState private var focused: Bool

    private var canAdd: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !tags.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add your own")
                        .font(.editorial(22, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("What's going on the plate, and what does it bring?")
                        .font(.display(13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
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

            TextField("a spoonful of peanut butter", text: $name)
                .font(.display(16, weight: .medium))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { focused = false }

            HStack(spacing: 8) {
                ForEach(Compound.allCases) { compound in
                    tagChip(compound)
                }
            }

            Button {
                Haptics.tap()
                onAdd(name.trimmingCharacters(in: .whitespaces), tags)
                dismiss()
            } label: {
                Text("Add it")
            }
            .buttonStyle(PrimaryButtonStyle())
            .opacity(canAdd ? 1 : 0.4)
            .disabled(!canAdd)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .task { focused = true }
    }

    private func tagChip(_ compound: Compound) -> some View {
        let isOn = tags.contains(compound)
        return Button {
            Haptics.soft()
            withAnimation(.spring(duration: 0.3)) {
                if isOn { tags.remove(compound) } else { tags.insert(compound) }
            }
        } label: {
            Text(compound.shortLabel)
                .font(.display(13, weight: .semibold))
                .foregroundStyle(isOn ? .white : compound.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(isOn ? AnyShapeStyle(compound.color) : AnyShapeStyle(compound.tint)))
        }
    }
}

// MARK: - Bits

/// "+ protein" pills, in trio order.
struct AddsPills: View {
    var adds: Set<Compound>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Compound.allCases.filter { adds.contains($0) }) { compound in
                Text("+ \(compound.shortLabel.lowercased())")
                    .font(.display(12, weight: .semibold))
                    .foregroundStyle(compound.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(compound.tint))
            }
        }
    }
}

/// The deck's card surface: a taller, softer take on `SoftCard` with an
/// optional colour wash and a live edge for the swipe states.
private struct DeckCard: ViewModifier {
    var wash: Color = .clear
    var edge: Color = .clear

    private let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background(
                shape
                    .fill(Palette.card)
                    .overlay(shape.fill(wash))
            )
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 1)
                    .overlay(shape.strokeBorder(edge, lineWidth: 2))
            )
            .shadow(color: Color(hex: "2E3A54").opacity(0.05), radius: 3, y: 2)
            .shadow(color: Color(hex: "2E3A54").opacity(0.10), radius: 28, y: 14)
    }
}

private extension View {
    func deckCard(wash: Color = .clear, edge: Color = .clear) -> some View {
        modifier(DeckCard(wash: wash, edge: edge))
    }
}
