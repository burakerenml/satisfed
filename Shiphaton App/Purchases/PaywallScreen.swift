//
//  PaywallScreen.swift
//  Shiphaton App
//
//  The app's own paywall, drawn in the app's own hand: canvas, aura, the
//  lit trio ring, serif headline, the same rounded rows as every other
//  choice in the app. RevenueCat still does the work underneath (offerings,
//  prices, trial eligibility, the purchase itself, restore), this is only
//  the face on it.
//
//  What App Review looks for is all on one screen: the full price and its
//  period next to the button, the trial's length and what it turns into,
//  Terms of Use and Privacy Policy, restore, and a close button that is
//  there from the first frame.
//

import RevenueCat
import SwiftUI

struct PaywallScreen: View {
    let reason: PaywallReason
    /// Given the customer info after a purchase or restore. Returns true
    /// when the entitlement is now active, which is what earns the
    /// "you're in" beat and closes the screen.
    let onUnlocked: (CustomerInfo) async -> Bool
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.layout) private var layout
    @State private var model: PaywallModel
    @State private var unlocked = false
    @State private var pulse = 0
    /// Flips once after the first frame; every section reveals off it in
    /// order.
    @State private var shown = false
    /// The pinned footer's real height, so the scroll content clears it
    /// exactly instead of by a guess.
    @State private var footerHeight: CGFloat = 220
    /// The scroll view's own height. The content is asked to be at least
    /// this tall, and the flexible gaps between its groups take up the
    /// difference, so the page fills the glass evenly on every phone
    /// instead of bunching at the top and leaving a hole above the button.
    @State private var viewportHeight: CGFloat = 0

    init(
        reason: PaywallReason,
        onUnlocked: @escaping (CustomerInfo) async -> Bool,
        onClose: @escaping () -> Void
    ) {
        self.reason = reason
        self.onUnlocked = onUnlocked
        self.onClose = onClose
        _model = State(initialValue: PaywallModel(reason: reason))
    }

    // MARK: - Rhythm

    /// The page's air scales with the glass: a mini tightens, a Max
    /// breathes.
    private var tall: Bool { layout.size.height >= 900 }
    /// The least air between groups. On a phone with room to spare the
    /// gaps grow past this, all by the same amount.
    private var gap: CGFloat { layout.isShort ? 18 : 26 }
    private var logoSize: CGFloat { tall ? 124 : 100 }
    private var margin: CGFloat { layout.isWide ? 28 : 24 }
    private var headlineSize: CGFloat { layout.isShort ? 28 : tall ? 32 : 30 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !layout.isShort {
                        PaywallLogoScene(size: logoSize)
                            .frame(maxWidth: .infinity)
                            .reveal(shown, order: 0)
                    }
                    words
                        .padding(.top, layout.isShort ? 12 : 8)
                        .reveal(shown, order: 1)
                    Spacer(minLength: gap)
                    // Pinned to their natural height, so the stack spends
                    // spare room on the spacers and never squeezes the rows
                    // (their text would shrink to its minimum scale).
                    benefits
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: gap)
                    planPicker
                        .fixedSize(horizontal: false, vertical: true)
                        .reveal(shown, order: 6)
                    // A little of the spare goes above the small print, but
                    // capped: the footer has its own air, and a wide gap
                    // there reads as a hole rather than as rhythm.
                    Spacer(minLength: 0)
                        .frame(maxHeight: 20)
                }
                .padding(.horizontal, margin)
                .padding(.top, layout.isShort ? 40 : 44)
                // Room for the pinned button block, so the last plan card
                // scrolls fully clear of it.
                .padding(.bottom, footerHeight + 8)
                .frame(minHeight: viewportHeight)
            }
            .scrollIndicators(.hidden)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .background(alignment: .top) {
                AuraBackdrop().ignoresSafeArea(edges: .top)
            }

            footer
                .reveal(shown, order: 7)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .disabled(model.phase == .working)
        .task { await model.load() }
        .onAppear {
            // A frame later, so the reveal has a "before" to animate from.
            DispatchQueue.main.async { shown = true }
        }
    }

    // MARK: - Top

    private var closeButton: some View {
        Button {
            Haptics.soft()
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Palette.card.opacity(0.9)))
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .padding(.trailing, margin - 4)
        .padding(.top, 8)
        .accessibilityLabel("Close")
        .reveal(shown, order: 0)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.remoteCopy["headline"] ?? headline)
                .font(.editorial(headlineSize, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // Only when the dashboard sets one: the benefit rows already
            // say what's inside.
            if let sub = model.remoteCopy["subheadline"] {
                Text(sub)
                    .font(.display(16, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headline: String {
        switch reason {
        case .loopFinished: "Let's make every meal this satisfying!"
        case .blocked: "Let's make this meal more satisfying!"
        case .chosen: "Let's make your meals more satisfying!"
        }
    }

    // MARK: - Benefits

    /// Four rows: the feature, then the one line of what it does for
    /// you. The last is the promise the other three keep.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: layout.isShort ? 12 : 16) {
            benefit("sparkles", tint: Palette.berry, "Craving translator", "Understand what you're really craving")
                .reveal(shown, order: 2)
            benefit("plus.circle.fill", tint: Palette.rose, "Add-on suggestions", "Make the foods you love more satisfying")
                .reveal(shown, order: 3)
            benefit("frying.pan.fill", tint: Palette.honey, "Recipe maker", "Satisfying meal ideas from your kitchen")
                .reveal(shown, order: 4)
            benefit("person.fill", tint: Palette.slate, "Made for you", "Every idea fits your goal and your diet")
                .reveal(shown, order: 5)
        }
    }

    private func benefit(_ symbol: String, tint: Color, _ title: String, _ line: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.display(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(line)
                    .font(.display(14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plans

    @ViewBuilder
    private var planPicker: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 10) {
                PlanCardPlaceholder()
                PlanCardPlaceholder()
            }
        case .unavailable:
            VStack(alignment: .leading, spacing: 12) {
                Text(model.notice ?? "Couldn't load the plans.")
                    .font(.display(15, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.soft()
                    Task { await model.load() }
                } label: {
                    Text("Try again")
                        .font(.display(15, weight: .semibold))
                        .foregroundStyle(Palette.roseDeep)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard()
        case .ready, .working:
            VStack(spacing: 10) {
                ForEach(model.plans) { plan in
                    PlanCard(plan: plan, isOn: model.selected == plan) {
                        Haptics.soft()
                        withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                            model.select(plan)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if unlocked {
                unlockedCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                VStack(spacing: 14) {
                    if let notice = model.notice, model.phase != .unavailable {
                        Text(notice)
                            .font(.display(13, weight: .medium))
                            .foregroundStyle(Palette.roseDeep)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    // The one line App Review reads most closely: the amount,
                    // the period, and with a trial, when the paying starts.
                    if let plan = model.selected {
                        Text(disclosure(for: plan))
                            .font(.display(13, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                            .transition(.opacity)
                    }
                    Button {
                        Haptics.tap()
                        pulse += 1
                        Task { await buy() }
                    } label: {
                        ZStack {
                            Text(model.remoteCopy["cta"] ?? cta)
                                .opacity(model.phase == .working ? 0 : 1)
                            if model.phase == .working {
                                ProgressView().tint(.white)
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .pulse(Capsule(), trigger: pulse)
                    .disabled(model.selected == nil || model.phase != .ready)
                    .opacity(model.phase == .ready || model.phase == .working ? 1 : 0.5)

                    legalRow
                }
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, 12)
        .padding(.bottom, layout.safeBottom > 0 ? 0 : 14)
        .background(
            // Canvas fading in over the last of the scroll, so the button
            // sits on solid ground without a hard edge above it.
            LinearGradient(
                stops: [
                    .init(color: Palette.canvas.opacity(0), location: 0),
                    .init(color: Palette.canvas, location: 0.3),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.top, -32)
            .ignoresSafeArea(edges: .bottom)
        )
        .animation(.spring(duration: 0.35, bounce: 0.15), value: unlocked)
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .animation(.easeOut(duration: 0.2), value: model.selectedID)
    }

    /// About what they get, not about the button. With a trial the button
    /// names its length, so the free part is read before the sheet; the
    /// price and terms are the line right above it either way.
    private var cta: String {
        guard let plan = model.selected else { return "Unlock Premium" }
        if let trial = plan.trial { return "Start \(trial.long) free trial" }
        return "Unlock Premium"
    }

    private func disclosure(for plan: PaywallPlan) -> String {
        if plan.term == .lifetime {
            return "\(plan.price) once. Yours for good."
        }
        if let trial = plan.trial {
            return "\(trial.long) free trial, then billed \(plan.price) \(plan.perTerm)."
        }
        return "Billed \(plan.price) \(plan.perTerm)."
    }

    private var legalRow: some View {
        HStack(spacing: 0) {
            legalLink("Restore") {
                Haptics.soft()
                Task { await restore() }
            }
            dot
            legalLink("Terms of Use") { openURL(Legal.termsOfUse) }
            dot
            legalLink("Privacy Policy") { openURL(Legal.privacyPolicy) }
        }
        .frame(maxWidth: .infinity)
    }

    private var dot: some View {
        Text("·")
            .font(.display(12, weight: .semibold))
            .foregroundStyle(Palette.inkSoft.opacity(0.5))
            .padding(.horizontal, 10)
    }

    private func legalLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.display(12, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
    }

    private var unlockedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.rose)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're in 💛")
                    .font(.editorial(20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Let's make the next meal more satisfying.")
                    .font(.display(13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.roseTint)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Palette.rose.opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func buy() async {
        guard let info = await model.buy() else { return }
        // A purchase that doesn't grant the entitlement would otherwise
        // leave the screen exactly as it was under someone who has just
        // paid. Restore already says so when it finds nothing; this is
        // the same courtesy for buying.
        let granted = await celebrate(if: info)
        if !granted { model.reportUnlockDidNotLand() }
    }

    private func restore() async {
        // `restore()` sets its own notice when it finds no subscription,
        // so nothing is added here on top of it.
        guard let info = await model.restore() else { return }
        await celebrate(if: info)
    }

    /// The good news, held for a beat so it's seen, then the screen goes.
    /// False when the entitlement didn't turn up, so the caller can say so.
    @discardableResult
    private func celebrate(if info: CustomerInfo) async -> Bool {
        guard await onUnlocked(info) else { return false }
        Haptics.success()
        unlocked = true
        try? await Task.sleep(for: .seconds(1.4))
        onClose()
        return true
    }
}

// MARK: - Reveal

/// Fade-and-rise entrance, staggered by `order`. Nothing moves under
/// Reduce Motion; it only fades.
private struct Reveal: ViewModifier {
    var shown: Bool
    var order: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .animation(.spring(duration: 0.7, bounce: 0.12).delay(0.05 + order * 0.07), value: shown)
    }
}

private extension View {
    func reveal(_ shown: Bool, order: Double) -> some View {
        modifier(Reveal(shown: shown, order: order))
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let plan: PaywallPlan
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isOn ? Palette.rose : Palette.hairline)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.display(17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    // The trial is on the card itself, not only on the
                    // button: it's the reason to pick this row.
                    if let trial = plan.trial {
                        Text("\(trial.long) free trial")
                            .font(.display(12, weight: .semibold))
                            .foregroundStyle(Palette.roseDeep)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                // The rate hangs off the price on the same baseline, the
                // way a shelf label reads: the amount, then what it buys.
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(plan.price)
                        .font(.display(19, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    if !plan.term.rate.isEmpty {
                        Text(plan.term.rate)
                            .font(.display(13, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isOn ? Palette.roseTint : Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isOn ? Palette.rose.opacity(0.45) : Palette.hairline, lineWidth: isOn ? 1.5 : 1)
                    )
                    .shadow(color: Color(hex: "2E3A54").opacity(isOn ? 0.06 : 0.03), radius: 14, y: 6)
            )
            .overlay(alignment: .topTrailing) {
                if let saving = plan.savingPercent {
                    Text("Save \(saving)%")
                        .font(.display(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Palette.roseGradient))
                        .offset(x: -14, y: -10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BounceStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

}

private struct PlanCardPlaceholder: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Palette.hairline).frame(width: 22, height: 22)
            Capsule().fill(Palette.hairline).frame(width: 80, height: 14)
            Spacer()
            Capsule().fill(Palette.hairline).frame(width: 70, height: 16)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - Logo scene

/// The app's mark, the bowl, on a soft rose glow. It settles in a beat
/// after the sheet appears, before the words do.
private struct PaywallLogoScene: View {
    var size: CGFloat
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.roseTint.opacity(0.7))
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: size * 0.3)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
            Image("satisfed_logo_transparent")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
        }
        .frame(height: size * 1.1)
        .animation(.spring(duration: 0.7, bounce: 0.2), value: shown)
        .onAppear {
            shown = false
            Task {
                try? await Task.sleep(for: .seconds(0.25))
                shown = true
            }
        }
        .accessibilityHidden(true)
    }
}
