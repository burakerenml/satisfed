//
//  OnboardingView.swift
//  Shiphaton App
//
//  The intro. Four short pages that show the idea rather than explain it
//  (the hook, the promise, the trio on the ring, the snap), then four
//  quick questions, then a hello. One picture and a couple of lines per
//  page; the Continue button and a swipe both move it along.
//
//  The picture pages carry no chrome at all. The questions get a back
//  chevron and one unbroken progress bar. Answers are written straight
//  into `ProfileKey`, the same values the You tab edits later. Finishing
//  flips `ProfileKey.didOnboard`, which `RootView` watches.
//

import SwiftUI

struct OnboardingView: View {
    /// Called from the last page's button. The root does the switch.
    var onFinish: () -> Void

    enum Step: Int, CaseIterable {
        case hook, promise, trio, snap
        case name, goal, diet, avoid
        case done

        var isIntro: Bool { rawValue <= Step.snap.rawValue }
        var isQuestion: Bool { rawValue >= Step.name.rawValue && rawValue <= Step.avoid.rawValue }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }

        /// How far through the questions this step is, 0 to 1.
        var questionProgress: Double {
            let count = Double(Step.avoid.rawValue - Step.name.rawValue + 1)
            return Double(rawValue - Step.name.rawValue + 1) / count
        }
    }

    @State private var step: Step
    @AppStorage(ProfileKey.name) private var name = ""
    @AppStorage(ProfileKey.goals) private var goalsRaw = ""
    @AppStorage(ProfileKey.goalCustom) private var goalCustom = ""
    @AppStorage(ProfileKey.diet) private var dietRaw = ""
    @AppStorage(ProfileKey.dietCustom) private var dietCustom = ""
    @AppStorage(ProfileKey.avoids) private var avoidsRaw = ""
    @AppStorage(ProfileKey.avoidCustom) private var avoidCustom = ""
    @FocusState private var nameFocused: Bool

    init(startAt step: Step = .hook, onFinish: @escaping () -> Void) {
        _step = State(initialValue: step)
        self.onFinish = onFinish
    }

    private var goals: Set<Goal> { Goal.decode(goalsRaw) }
    private var diet: Diet? { Diet(rawValue: dietRaw) }
    private var avoids: Set<Avoid> { Avoid.decode(avoidsRaw) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ZStack {
                    switch step {
                    case .hook: hookPage.transition(pageTransition)
                    case .promise: promisePage.transition(pageTransition)
                    case .trio: trioPage.transition(pageTransition)
                    case .snap: snapPage.transition(pageTransition)
                    case .name: namePage.transition(pageTransition)
                    case .goal: goalPage.transition(pageTransition)
                    case .diet: dietPage.transition(pageTransition)
                    case .avoid: avoidPage.transition(pageTransition)
                    case .done: donePage.transition(pageTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(swipe, including: step.isIntro ? .all : .none)
                continueButton
            }
            .padding(.horizontal, Metrics.screenMargin)
        }
        .background(alignment: .top) {
            AuraBackdrop().ignoresSafeArea(edges: .top)
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: step)
    }

    /// The app's soft push between steps, same as the log flow.
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity
        )
    }

    // MARK: - Moving along

    private func go(to next: Step?) {
        guard let next else { return }
        Haptics.soft()
        nameFocused = false
        step = next
    }

    private func advance() {
        if step == .done {
            Haptics.success()
            onFinish()
        } else {
            go(to: step.next)
        }
    }

    private func goBack() {
        go(to: step.previous)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -50 {
                    advance()
                } else if value.translation.width > 50 {
                    goBack()
                }
            }
    }

    /// Continue is held back only where an answer is the whole point.
    private var canContinue: Bool {
        switch step {
        case .goal: !goals.isEmpty || hasText(goalCustom)
        case .diet: diet != nil || hasText(dietCustom)
        default: true
        }
    }

    private var buttonTitle: String {
        switch step {
        case .hook: "Tell me more"
        case .snap: "Let's meet"
        case .avoid: avoids.isEmpty && !hasText(avoidCustom) ? "Nothing to avoid" : "Continue"
        case .done: "Let's go"
        default: "Continue"
        }
    }

    // MARK: - Chrome

    /// Empty over the picture pages and the hello. Over the questions: a
    /// back chevron and the progress bar, centred on the screen.
    private var topBar: some View {
        ZStack {
            if step.isQuestion {
                ProgressBar(progress: step.questionProgress)
                HStack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                }
            }
        }
        .frame(height: 44)
        .padding(.top, 4)
    }

    private var continueButton: some View {
        Button(action: advance) {
            Text(buttonTitle)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: buttonTitle)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.45)
        .animation(.easeOut(duration: 0.2), value: canContinue)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Page frames

    /// Picture on top, words underneath.
    private func showPage<Visual: View>(
        headline: String,
        line: String,
        @ViewBuilder visual: () -> Visual
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            visual()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            words(headline: headline, line: line)
                .padding(.bottom, 22)
        }
    }

    /// Words on top, the answer under them. Scrolls, so a keyboard under a
    /// long list still leaves every row reachable.
    private func askPage<Answer: View>(
        headline: String,
        line: String? = nil,
        @ViewBuilder answer: () -> Answer
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                words(headline: headline, line: line)
                answer()
            }
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func words(headline: String, line: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.editorial(30, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let line {
                Text(line)
                    .font(.display(16, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Intro pages

    private var hookPage: some View {
        showPage(
            headline: "Tired of micromanaging your body?",
            line: "The counting. The rules. The guilt after every bite."
        ) {
            DietTalkScene()
        }
    }

    private var promisePage: some View {
        showPage(
            headline: "Nothing comes off your plate.",
            line: "We make the meals you already love more satisfying. So you feel full, steady and free around food."
        ) {
            PlateScene()
        }
    }

    private var trioPage: some View {
        showPage(
            headline: "Three builders do the work.",
            line: "Each one adds staying power. Together they make a meal that lasts."
        ) {
            TrioExplainerScene()
        }
    }

    private var snapPage: some View {
        showPage(
            headline: "Snap your food. We do the rest.",
            line: "Point the camera at whatever you're eating. We'll suggest easy adds that make it more satisfying."
        ) {
            DemoVideoScene()
                .padding(.vertical, 8)
        }
    }

    // MARK: - Questions

    private var namePage: some View {
        askPage(headline: "Before we begin, let's meet.", line: "What should we call you?") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Your name", text: $name)
                    .font(.display(26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($nameFocused)
                    .onSubmit(advance)
                Capsule()
                    .fill(nameFocused ? Palette.rose : Palette.hairline)
                    .frame(height: 2)
                    .animation(.easeOut(duration: 0.2), value: nameFocused)

                if !trimmedName.isEmpty {
                    WelcomeLine(name: trimmedName)
                        .padding(.top, 22)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .padding(.top, 6)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: trimmedName.isEmpty)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true }
        }
    }

    private var goalPage: some View {
        askPage(headline: "What would you like more of?", line: "Pick all that fit, or say it your way.") {
            VStack(spacing: 8) {
                ForEach(Goal.allCases) { option in
                    ChoiceRow(label: option.label, isOn: goals.contains(option)) {
                        var set = goals
                        if set.contains(option) { set.remove(option) } else { set.insert(option) }
                        goalsRaw = Goal.encode(set)
                    }
                }
                CustomAnswerField(text: $goalCustom)
            }
        }
    }

    private var dietPage: some View {
        askPage(headline: "How do you eat?", line: "So every suggestion fits.") {
            VStack(spacing: 8) {
                ForEach(Diet.allCases) { option in
                    ChoiceRow(label: option.label, isOn: diet == option) {
                        dietRaw = option.rawValue
                    }
                }
                CustomAnswerField(text: $dietCustom)
            }
        }
    }

    private var avoidPage: some View {
        askPage(headline: "What do you keep off the table?", line: "Pick all that apply. Dislikes count too.") {
            VStack(spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Avoid.allCases) { option in
                        ChoiceRow(label: option.label, isOn: avoids.contains(option), compact: true) {
                            var set = avoids
                            if set.contains(option) { set.remove(option) } else { set.insert(option) }
                            avoidsRaw = Avoid.encode(set)
                        }
                    }
                }
                OwnAnswersField(text: $avoidCustom)
            }
        }
    }

    // MARK: - Done

    private var donePage: some View {
        showPage(
            headline: trimmedName.isEmpty ? "You're all set." : "Nice to meet you, \(trimmedName).",
            line: "Let's make your next meal more satisfying."
        ) {
            AllSetScene()
        }
    }
}
