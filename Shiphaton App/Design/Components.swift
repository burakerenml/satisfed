//
//  Components.swift
//  Shiphaton App
//
//  Shared visual components: the trio ring, compound chips, boost pills,
//  the meal thumbnail and the swipe-to-remove wrapper.
//

import SwiftUI
import UIKit

// MARK: - Trio ring

/// The signature visual: a ring in three segments — protein, fibre,
/// healthy fats. Segments simply light up when present. No numbers.
struct TrioRing: View {
    var compounds: Set<Compound>
    var size: CGFloat = 44
    var lineWidth: CGFloat = 5
    /// Absent segments in the builder's own color at whisper opacity instead
    /// of the neutral track — reads as an invitation, never a gap.
    var pastelTrack = false

    private let gap = 0.045

    var body: some View {
        ZStack {
            ForEach(Array(Compound.allCases.enumerated()), id: \.element) { index, compound in
                let start = Double(index) / 3 + gap / 2
                let end = Double(index + 1) / 3 - gap / 2
                Circle()
                    .trim(from: start, to: end)
                    .stroke(
                        compounds.contains(compound)
                            ? compound.color
                            : pastelTrack ? compound.color.opacity(0.18) : Palette.track,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: compounds.contains(compound) ? compound.color.opacity(0.35) : .clear,
                        radius: lineWidth * 0.8, y: 1
                    )
                    .animation(.spring(duration: 0.55, bounce: 0.35), value: compounds)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let present = Compound.allCases.filter { compounds.contains($0) }.map(\.label)
        return present.isEmpty ? "No satisfaction builders yet" : "Includes \(present.joined(separator: ", "))"
    }
}

// MARK: - Compound chip

struct CompoundChip: View {
    var compound: Compound
    var filled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(filled ? compound.color : compound.color.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(compound.label)
                .font(.display(12, weight: .semibold))
                .foregroundStyle(filled ? compound.color : Palette.inkSoft)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(filled ? compound.tint : compound.tint.opacity(0.45))
        )
    }
}

// MARK: - Emoji tile

/// A rounded square holding a large emoji — the visual anchor of a meal.
struct EmojiTile: View {
    var emoji: String
    var size: CGFloat = 54
    var background: Color = Palette.blush

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay(
                Text(emoji)
                    .font(.system(size: size * 0.5))
            )
    }
}

// MARK: - Meal thumbnail

/// The snapped photo at the head of a meal row, when there is one.
///
/// Deliberately photo-only: a meal logged without a picture falls back to the
/// trio ring on a tinted tile, never a stand-in emoji, letter or icon, so the
/// row stays about the food itself and what it brought.
struct MealThumbnail: View {
    var image: UIImage
    var size: CGFloat = 54

    private var radius: CGFloat { size * 0.32 }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.editorial(21, weight: .semibold))
                .foregroundStyle(Palette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.display(14, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Primary button

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(Palette.roseGradient)
                    .shadow(color: Palette.roseDeep.opacity(0.35), radius: 12, y: 5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Press bounce

/// Gentle scale-on-press for tappable cards.
struct BounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Card bounce plus a soft rose wash under the finger. Grid tiles often
/// leave the screen the moment they're let go, so the press itself has to
/// be the thing that's felt.
struct TapTileStyle: ButtonStyle {
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let pressed = configuration.isPressed
        return configuration.label
            .overlay {
                shape
                    .fill(Palette.rose.opacity(pressed ? 0.12 : 0))
                    .overlay(
                        shape.strokeBorder(Palette.rose.opacity(pressed ? 0.45 : 0), lineWidth: 1.5)
                    )
                    .allowsHitTesting(false)
            }
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: pressed)
    }
}

// MARK: - Press pulse

/// A ring that rides outward from a control and fades, once per tap. For
/// buttons that fire and then get out of the way: a tinted wash on those
/// would read as "this is switched on now", which is never what they mean.
///
/// `trigger` is bumped by the button's own action, so the ring only ever
/// answers a tap that actually did something.
struct PulseRing<S: Shape>: ViewModifier {
    var shape: S
    var color: Color
    var trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 at the tap, 1 spent. Starts spent, so nothing shows until a tap.
    @State private var wave: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .overlay {
                shape
                    .stroke(color.opacity(0.5 * Double(1 - wave)), lineWidth: 2.5)
                    .scaleEffect(1 + 0.38 * wave)
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                wave = 0
                withAnimation(.easeOut(duration: 0.5)) { wave = 1 }
            }
    }
}

extension View {
    /// Sends a soft ring out from this control every time `trigger` changes.
    func pulse<S: Shape>(_ shape: S, trigger: Int, color: Color = Palette.rose) -> some View {
        modifier(PulseRing(shape: shape, color: color, trigger: trigger))
    }
}

// MARK: - Swipe to remove

/// Drag a card to the left to reveal a soft remove button, iOS-mail style.
/// Used for logged meals, so anything snapped or logged by mistake can be
/// taken back off the day.
///
/// The offset is plain state rather than `@GestureState`: a gesture-state
/// value snaps back to zero the instant the finger lifts, which flashed the
/// button out and back in before the settle animation caught up. Owning the
/// offset means the card hands off from finger to spring in one continuous
/// motion.
struct SwipeToRemove<Content: View>: View {
    var onRemove: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var isOpen = false

    private let reveal: CGFloat = 84
    /// How far past the button the card can be pulled before it stops.
    private let stretch: CGFloat = 26

    /// 0 closed, 1 fully revealed. Drives the button's fade and grow so it
    /// tracks the finger instead of popping in.
    private var progress: Double {
        Double(max(0, min(-offset, reveal)) / reveal)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            removeButton
                .opacity(progress)
                .scaleEffect(0.82 + 0.18 * progress, anchor: .trailing)
                // Only tappable once it is essentially all the way out, so a
                // half-open card can never be removed by a stray tap.
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
            content
                .offset(x: offset)
                .gesture(swipe)
        }
    }

    private var removeButton: some View {
        Button {
            close()
            onRemove()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .semibold))
                Text("Remove")
                    .font(.display(11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: reveal - 10)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.roseGradient)
            )
        }
        .buttonStyle(BounceStyle())
        .accessibilityLabel("Remove")
    }

    /// Horizontal only: a drag that starts out more vertical than sideways is
    /// left entirely to the scroll view.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragStart == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragStart = offset
                }
                guard let start = dragStart else { return }
                offset = resisted(start + value.translation.width)
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                dragStart = nil
                // Let a flick finish the gesture the user started.
                let projected = offset + value.predictedEndTranslation.width * 0.25
                settle(open: projected < -reveal * 0.5)
            }
    }

    /// Rubber-banding at both ends: the card never runs away past the button,
    /// and never slides right off a closed card.
    private func resisted(_ x: CGFloat) -> CGFloat {
        if x > 0 { return x * 0.18 }
        if x < -reveal { return -reveal - (-reveal - x) * 0.32 }
        return x
    }

    private func settle(open: Bool) {
        if open != isOpen { Haptics.soft() }
        withAnimation(.spring(duration: 0.38, bounce: 0.18)) {
            isOpen = open
            offset = open ? -reveal : 0
        }
    }

    private func close() {
        withAnimation(.spring(duration: 0.34, bounce: 0.16)) {
            isOpen = false
            offset = 0
        }
    }
}

// MARK: - Choice row

/// One answer in a profile question: a rounded row with a check when
/// chosen. Used by onboarding and by the You tab's answer sheets, so the
/// two never drift apart. `compact` is the grid-cell size for short
/// multi-select words.
struct ChoiceRow: View {
    var label: String
    var isOn: Bool
    var compact = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.soft()
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                action()
            }
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 18 : 20, weight: .medium))
                    .foregroundStyle(isOn ? Palette.rose : Palette.hairline)
            }
            .padding(.horizontal, compact ? 14 : 16)
            .padding(.vertical, compact ? 12 : 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isOn ? Palette.roseTint : Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isOn ? Palette.rose.opacity(0.35) : Palette.hairline, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BounceStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Aura backdrop

/// Blurred tonal washes that sit behind the top of a screen, so the canvas
/// feels lit rather than flat. Purely decorative; fixed while content scrolls.
struct AuraBackdrop: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.roseTint.opacity(0.55))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -120, y: -130)
            Circle()
                .fill(Palette.honeyTint.opacity(0.50))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 150, y: -60)
            Circle()
                .fill(Palette.mist.opacity(0.45))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 60, y: 140)
        }
        .frame(height: 380)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Custom answer field

/// The "in your own words" row under a question's presets: a text box in
/// the same rounded card as `ChoiceRow`, which tints itself like a chosen
/// answer once something is written.
struct CustomAnswerField: View {
    @Binding var text: String
    var placeholder = "Something else"
    @FocusState private var focused: Bool

    private var filled: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .font(.display(15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($focused)
            Image(systemName: filled ? "checkmark.circle.fill" : "square.and.pencil")
                .font(.system(size: filled ? 20 : 17, weight: .medium))
                .foregroundStyle(filled ? Palette.rose : Palette.inkSoft.opacity(0.7))
                .animation(.spring(duration: 0.3, bounce: 0.2), value: filled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(filled ? Palette.roseTint : Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            filled ? Palette.rose.opacity(0.35) : (focused ? Palette.rose.opacity(0.5) : Palette.hairline),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeOut(duration: 0.2), value: filled)
        .animation(.easeOut(duration: 0.2), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

// MARK: - Own answers field

/// The "in your own words" answer for a question that can take several:
/// what's already been added sits above as rose chips, each with its own
/// remove, and the same rounded box as `CustomAnswerField` takes the next
/// one. Return or the plus adds it and keeps the keyboard up for another.
/// The items live in one comma-joined string (see `ProfileAnswers.list`),
/// so the stored value and every reader stay as they were.
struct OwnAnswersField: View {
    @Binding var text: String
    var placeholder = "Something else"
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var items: [String] { ProfileAnswers.list(text) }
    private var canAdd: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(items, id: \.self) { item in
                        chip(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            field
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: items)
    }

    private func chip(_ item: String) -> some View {
        Button {
            Haptics.soft()
            remove(item)
        } label: {
            HStack(spacing: 8) {
                Text(item)
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.rose)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.roseTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Palette.rose.opacity(0.35), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BounceStyle())
        .accessibilityLabel(item)
        .accessibilityHint("Removes it")
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private var field: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $draft)
                .font(.display(15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(add)
            Button(action: add) {
                Image(systemName: canAdd ? "plus.circle.fill" : "square.and.pencil")
                    .font(.system(size: canAdd ? 22 : 17, weight: .medium))
                    .foregroundStyle(canAdd ? Palette.rose : Palette.inkSoft.opacity(0.7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .accessibilityLabel("Add")
            .animation(.spring(duration: 0.3, bounce: 0.2), value: canAdd)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(focused ? Palette.rose.opacity(0.5) : Palette.hairline, lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.2), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    /// Takes the draft as one more item. A repeat of something already
    /// there just clears the box. Focus stays so the next one can follow.
    private func add() {
        let item = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty else { return }
        Haptics.soft()
        text = ProfileAnswers.encodeList(items + [item])
        draft = ""
        focused = true
    }

    private func remove(_ item: String) {
        text = ProfileAnswers.encodeList(items.filter { $0 != item })
    }
}

// MARK: - Notice banner

/// One line of "here's what happened", with an icon that says which kind:
/// a warm honey nudge for something the person can fix themselves, a cool
/// slate note for the network being out. Never a raw error, never red.
struct NoticeBanner: View {
    enum Kind {
        case nudge
        case offline
        case trouble

        var symbol: String {
            switch self {
            case .nudge: "camera.metering.unknown"
            case .offline: "wifi.slash"
            case .trouble: "exclamationmark.bubble"
            }
        }

        var color: Color {
            switch self {
            case .nudge: Palette.honey
            case .offline: Palette.slate
            case .trouble: Palette.honey
            }
        }

        var tint: Color {
            switch self {
            case .nudge: Palette.honeyTint
            case .offline: Palette.slateTint
            case .trouble: Palette.honeyTint
            }
        }
    }

    var text: String
    var kind: Kind = .trouble
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol ?? kind.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(kind.color)
                .frame(width: 20)
            Text(text)
                .font(.display(13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(kind.tint))
        .accessibilityElement(children: .combine)
    }

    /// Picks offline vs trouble from the error itself.
    static func kind(for error: Error) -> Kind {
        AIError.isOffline(error) || !NetworkMonitor.shared.isOnline ? .offline : .trouble
    }
}

// MARK: - Recipe step

/// One step of the making: its number in a small rose disc, then the
/// sentence, hanging off the same baseline. Shared by the chef's cards in
/// the recipe maker and by a saved plate opened from Today or History, so
/// a plate reads the same wherever it is met.
struct StepRow: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.display(12, weight: .bold))
                .foregroundStyle(Palette.roseDeep)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.roseTint))
            Text(text)
                .font(.display(14, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Health disclaimer

/// The line that belongs on every screen handing out food ideas, without
/// turning into a wall of legal text. Folded it is one quiet sentence in
/// the secondary grey; a tap opens the whole note underneath and a second
/// tap puts it away. No card, no banner, no colour: it sits at the foot of
/// a section and never asks for a turn.
struct HealthDisclaimer: View {
    /// Deliberately not saved. This is a footnote, not a setting, so it
    /// reads the same way on every visit and can always be opened again.
    @State private var isOpen = false

    private static let summary = "Ideas, not medical advice. Always check what's in it yourself."

    private static let full = """
    satisfed offers everyday food ideas. It is not medical or dietary \
    advice, and it is no substitute for a dietitian or a doctor.

    The ideas are put together by AI, so they can get things wrong. Every \
    suggestion is an idea, not a promise. Always check what's in a food \
    yourself before you eat it. If you are pregnant, taking medication, or \
    managing a health condition, talk it through with a professional first.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(Self.summary)
                        .font(.display(12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.inkSoft)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides the full note" : "Reads the full note")

            if isOpen {
                Text(Self.full)
                    .font(.display(12, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Premium lock card

/// What a screen shows once the free round is spent and the paywall has
/// been asked for: the same card everywhere, so it reads as one door
/// rather than a different refusal per screen. `line` says what Premium
/// keeps going on this particular screen; `trailing` is anything that
/// still works without paying (typing the meal in, say).
struct PremiumLockCard<Trailing: View>: View {
    var line: String
    @ViewBuilder var trailing: () -> Trailing

    init(line: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.line = line
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.rose)
                .padding(.top, 6)
            Text("Join satisfed Premium")
                .font(.editorial(22, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(line)
                .font(.display(14, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
            Button {
                Haptics.tap()
                PaywallCenter.shared.request(.blocked)
            } label: {
                Text("Join Premium")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
            trailing()
        }
        .frame(maxWidth: .infinity)
        .softCard(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

extension PremiumLockCard where Trailing == EmptyView {
    init(line: String) {
        self.init(line: line) { EmptyView() }
    }
}

// MARK: - Flow layout

/// Lays its children out left to right, wrapping onto a new line when the
/// next one won't fit: chips and tags of uneven width, the way words wrap.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: SwiftUI.Layout.Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: SwiftUI.Layout.Subviews, cache: inout ()) {
        let placed = place(in: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize.unspecified
            )
        }
    }

    private func place(in width: CGFloat, subviews: SwiftUI.Layout.Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + lineHeight), origins)
    }
}
