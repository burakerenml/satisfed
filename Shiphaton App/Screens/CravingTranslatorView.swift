//
//  CravingTranslatorView.swift
//  Shiphaton App
//
//  Craving translator: say what's calling in your own words, get a warm
//  read on what it might mean, then honor it — the craving stays,
//  staying power joins. Nothing is suggested up front: showing foods to
//  someone who's craving only plants more cravings.
//
//  The read is AI-written: the typed craving, the latest energy check-in,
//  and the last week of logged meals and cravings go to the translator
//  bot, which answers with what the body is plausibly asking for. There
//  is no canned line under it: while the bot reads, the card shows only
//  that it's reading, and if the call can't land, it says so and nothing
//  generic stands in for the answer.
//

import SwiftUI
import SwiftData

struct CravingTranslatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]
    @Query(sort: \EnergyCheck.date, order: .reverse) private var energyChecks: [EnergyCheck]

    /// What's being typed.
    @State private var draft = ""
    /// The craving that was sent off, in the person's own words.
    @State private var asked: String?
    @State private var translation: CravingTranslation?
    @State private var isTranslating = false
    /// Why the read didn't arrive, when it didn't.
    @State private var readNotice: String?
    @State private var readNoticeKind: NoticeBanner.Kind = .trouble
    /// The free round is spent: the lock card stands where the read would.
    @State private var readLocked = false
    @State private var translationTask: Task<Void, Never>?
    @FocusState private var isEditing: Bool

    #if DEBUG
    /// Screenshot hook: launch with "-uicraving crunchy" to ask up front.
    private func applyDebugLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uicraving"), index + 1 < arguments.count {
            draft = arguments[index + 1]
            ask()
        }
    }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What are you craving?")
                                .font(.editorial(24, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text("Cravings aren't problems, they're information.")
                                .font(.display(14, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                        }

                        cravingField

                        if let asked {
                            if readLocked {
                                PremiumLockCard(line: "Your free round is done. Join to keep the craving reads coming, whenever one calls.")
                                    .transition(.opacity.combined(with: .offset(y: 8)))
                            } else {
                                if let readNotice {
                                    NoticeBanner(text: readNotice, kind: readNoticeKind)
                                        .transition(.opacity.combined(with: .offset(y: 8)))
                                }
                                if isTranslating {
                                    readingCard(for: asked)
                                } else if let translation {
                                    translationCard(translation, for: asked)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .animation(.spring(duration: 0.45, bounce: 0.2), value: asked)
            .onAppear {
                #if DEBUG
                applyDebugLaunchArguments()
                #endif
                // Text-first screen: the keyboard is up before the first tap.
                if asked == nil { isEditing = true }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Craving translator")
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
        }
        .onDisappear { translationTask?.cancel() }
        // Subscribing here means the read they asked for arrives, rather
        // than leaving them wondering what they just paid for.
        .paywallHost { if let asked { translate(asked) } }
    }

    // MARK: - The question

    /// One free-text box. No taste chips, no food shortcuts: the person
    /// says it however it comes out, and the send button reads it.
    private var cravingField: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Say it in your own words", text: $draft, axis: .vertical)
                .font(.display(17, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2...5)
                .focused($isEditing)
                .submitLabel(.send)
                .onSubmit(ask)

            HStack(spacing: 10) {
                if asked != nil {
                    Button {
                        clear()
                    } label: {
                        Text("Start over")
                            .font(.display(13, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Palette.canvas)
                                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                            )
                    }
                    .buttonStyle(BounceStyle())
                }
                Spacer(minLength: 0)
                Button(action: ask) {
                    HStack(spacing: 6) {
                        Text(asked == nil ? "Read it" : "Read again")
                            .font(.display(14, weight: .semibold))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Palette.roseGradient))
                    .opacity(canAsk ? 1 : 0.4)
                }
                .buttonStyle(BounceStyle())
                .disabled(!canAsk)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAsk: Bool { !trimmedDraft.isEmpty }

    // MARK: - Asking and the AI read

    private func ask() {
        let craving = trimmedDraft
        guard !craving.isEmpty else { return }
        Haptics.soft()
        isEditing = false
        asked = craving
        CravingLog.record(craving)
        translate(craving)
    }

    private func clear() {
        translationTask?.cancel()
        draft = ""
        asked = nil
        translation = nil
        isTranslating = false
        readNotice = nil
        readLocked = false
    }

    /// The latest energy check-in from the last few hours, folded into the
    /// context so the translator knows how the day feels without asking.
    private var moodNote: String? {
        guard let latest = energyChecks.first,
              Date.now.timeIntervalSince(latest.date) < 4 * 3600 else { return nil }
        return "feeling \(latest.level.label.lowercased())"
    }

    private func translate(_ craving: String) {
        translationTask?.cancel()
        translation = nil
        readNotice = nil
        readLocked = false
        // Spent free round: the paywall is the answer, not a spinner that
        // ends in a refusal.
        if SubscriptionStore.shared.needsSubscription {
            isTranslating = false
            readLocked = true
            PaywallCenter.shared.request(.blocked)
            return
        }
        if !NetworkMonitor.shared.isOnline {
            isTranslating = false
            readNoticeKind = .offline
            readNotice = "You're offline, so the read can't come through. Connect and tap Read again."
            return
        }
        isTranslating = true
        let note = moodNote ?? ""
        let userData = RecentData.payload(meals: meals, energyChecks: energyChecks)
        translationTask = Task {
            var result: CravingTranslation?
            var failure: Error?
            do {
                result = try await ComboAIClient.translateCraving(
                    craving: craving, note: note, userData: userData,
                    profile: ProfileContext.aiProfile()
                )
            } catch {
                failure = error
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                translation = result
                isTranslating = false
                if let failure {
                    if case AIError.paywallRequired = failure {
                        // The paywall is already on its way up.
                        readNotice = nil
                        readLocked = true
                    } else {
                        readNoticeKind = NoticeBanner.kind(for: failure)
                        readNotice = AIError.friendlyMessage(for: failure, what: "give you the read")
                    }
                }
            }
            // One read is the whole free go, if that's what this was. The
            // paywall follows on the good news after a beat, the same way
            // it follows the plate summary.
            if result != nil { await offerSubscriptionIfLoopSpent() }
        }
    }

    /// The gate is asked again once the read is on screen, so the next
    /// ask meets the paywall up front, and the soft offer lands after a
    /// beat, once the read has actually been seen.
    private func offerSubscriptionIfLoopSpent() async {
        await SubscriptionStore.shared.refreshGateState()
        guard SubscriptionStore.shared.needsSubscription else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        PaywallCenter.shared.offerAfterFreeLoop()
    }

    // MARK: - Translation

    /// The card while the bot is reading: the label and the spinner, and
    /// nothing standing in for the answer.
    private func readingCard(for asked: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("THE READ", color: Palette.roseDeep)
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Palette.rose)
                Text("Reading it…")
                    .font(.display(13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.blush)
        )
        .id("reading-\(asked)")
        .transition(.opacity.combined(with: .offset(y: 12)))
    }

    private func translationCard(_ translation: CravingTranslation, for asked: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let headline = translation.headline.nonEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("THE READ", color: Palette.roseDeep)
                    Text(headline)
                        .font(.editorial(16))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(3)
                }
            }
            if let talk = translation.bodyTalk.nonEmpty {
                Text(talk)
                    .font(.display(14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(3)
            }

            if !translation.bodyNeeds.isEmpty {
                let needs = translation.bodyNeeds
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("WHAT YOUR BODY'S ASKING FOR", color: Palette.berry)
                    ForEach(needs, id: \.self) { need in
                        needBadge(need)
                    }
                }
            }

            if !translation.signals.isEmpty {
                let signals = translation.signals
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("THE SIGNALS", color: Palette.slate)
                    ForEach(signals) { signal in
                        HStack(alignment: .top, spacing: 10) {
                            Text(signal.emoji.nonEmpty ?? "✨")
                                .font(.system(size: 18))
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.name)
                                    .font(.display(14, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Text(signal.why)
                                    .font(.display(13, weight: .medium))
                                    .foregroundStyle(Palette.inkSoft)
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
            }

            if !translation.oftenQuietsIt.isEmpty {
                // These lines name foods, so they pass the same net as
                // every other suggestion. A line that reaches for
                // something off the table simply isn't there.
                let quiets = DietaryFilter.keep(translation.oftenQuietsIt, name: { $0 })
                if !quiets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("WHAT OFTEN QUIETS IT", color: Palette.slate)
                        ForEach(quiets, id: \.self) { line in
                            Text(line)
                                .font(.display(13, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .lineSpacing(2)
                        }
                    }
                }
            }

            if let fact = translation.worthKnowing.nonEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("WORTH KNOWING", color: Palette.honey)
                    Text(fact)
                        .font(.display(14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(3)
                }
            }

            if let checkIn = translation.checkIn.nonEmpty {
                Text(checkIn)
                    .font(.display(13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(2)
            }

            if let close = translation.coachNote.nonEmpty {
                Text(close)
                    .font(.editorial(15))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.blush)
        )
        // New id per ask so a fresh question re-runs the entrance transition.
        .id(asked)
        .transition(.opacity.combined(with: .offset(y: 12)))
    }

    /// One thing the body is asking for: a white pill with a berry dot,
    /// the same chip language as the rest of the app, so it sits lightly
    /// on the blush card instead of shouting in pink on pink.
    private func needBadge(_ need: String) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Palette.berry)
                .frame(width: 6, height: 6)
            Text(need)
                .font(.display(14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.leading, 13)
        .padding(.trailing, 15)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Palette.card)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        )
    }

    private func sectionLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.display(11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

private extension String {
    /// `nil` for an empty string, so `??` can fall through to a default.
    var nonEmpty: String? { isEmpty ? nil : self }
}
