//
//  OnboardingScenes.swift
//  Shiphaton App
//
//  The pictures the intro is made of. Each scene owns its own little
//  timeline (a Task that sleeps between beats and is cancelled the moment
//  the page leaves), so every page plays from the top whenever it shows.
//  Text stays out of here: the pages in OnboardingView write the words.
//

import SwiftUI
import AVFoundation

// MARK: - Progress bar

/// One unbroken track for the questions: the rose fill springs to each
/// new step, with a soft glow so the move reads without any fuss.
struct ProgressBar: View {
    /// 0 to 1.
    var progress: Double
    var width: CGFloat = 150

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Palette.ink.opacity(0.1))
            Capsule()
                .fill(Palette.roseGradient)
                .frame(width: max(10, width * progress))
                .shadow(color: Palette.rose.opacity(0.45), radius: 6, y: 1)
        }
        .frame(width: width, height: 6)
        .animation(.spring(duration: 0.7, bounce: 0.18), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

// MARK: - Welcome line

/// "Welcome, Maya!" written out letter by letter. Each character the
/// person types slides in on its own, and a name that's already there
/// on arrival types itself out.
struct WelcomeLine: View {
    var name: String

    /// How many characters of the name are on screen.
    @State private var shown = 0
    @State private var typing: Task<Void, Never>?

    private var visible: [Character] { Array(name.prefix(shown)) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Welcome, ")
            ForEach(Array(visible.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.6, anchor: .bottom)),
                        removal: .opacity
                    ))
            }
            Text("!")
        }
        .font(.editorial(26, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .animation(.spring(duration: 0.38, bounce: 0.3), value: visible)
        .onChange(of: name, initial: true) { _, newName in retarget(newName.count) }
        .onDisappear { typing?.cancel() }
        .accessibilityLabel("Welcome, \(name)!")
    }

    /// Deleting cuts straight away; adding writes out one letter at a time.
    private func retarget(_ target: Int) {
        typing?.cancel()
        if shown > target { shown = target }
        guard shown < target else { return }
        typing = Task {
            while shown < target {
                guard !Task.isCancelled else { return }
                shown += 1
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }
}

// MARK: - Scene 1: diet talk, crossed out

/// The words the hook is tired of, drifting on the canvas and getting a
/// rose line drawn through them one by one.
struct DietTalkScene: View {
    private struct Pill: Identifiable {
        let id: Int
        let word: String
        let x: CGFloat
        let y: CGFloat
        let tilt: Double
    }

    private let pills: [Pill] = [
        Pill(id: 0, word: "calories", x: -92, y: -104, tilt: -6),
        Pill(id: 1, word: "macros", x: 86, y: -112, tilt: 5),
        Pill(id: 2, word: "cheat day", x: -22, y: -36, tilt: -2),
        Pill(id: 3, word: "off limits", x: 106, y: 8, tilt: 6),
        Pill(id: 4, word: "guilt", x: -114, y: 44, tilt: 4),
        Pill(id: 5, word: "portion control", x: 28, y: 112, tilt: -4),
    ]

    @State private var struck = 0
    @State private var drifting = false
    @State private var timeline: Task<Void, Never>?

    var body: some View {
        ZStack {
            ForEach(pills) { pill in
                pillView(pill)
                    .rotationEffect(.degrees(pill.tilt))
                    .offset(x: pill.x, y: pill.y + (drifting ? drift(for: pill) : 0))
                    .animation(
                        .easeInOut(duration: 2.6 + Double(pill.id) * 0.2)
                            .repeatForever(autoreverses: true)
                            .delay(Double(pill.id) * 0.15),
                        value: drifting
                    )
            }
        }
        .frame(width: 340, height: 290)
        .onAppear(perform: play)
        .onDisappear { timeline?.cancel() }
        .accessibilityElement()
        .accessibilityLabel("Calories, macros, cheat days, guilt: all crossed out.")
    }

    private func drift(for pill: Pill) -> CGFloat {
        pill.id.isMultiple(of: 2) ? -5 : 5
    }

    private func pillView(_ pill: Pill) -> some View {
        let isStruck = pill.id < struck
        return Text(pill.word)
            .font(.display(17, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Palette.card)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                    .shadow(color: Color(hex: "2E3A54").opacity(0.06), radius: 10, y: 5)
            )
            .overlay {
                StrikeLine()
                    .trim(from: 0, to: isStruck ? 1 : 0)
                    .stroke(Palette.roseDeep, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .padding(.horizontal, 8)
                    .animation(.easeOut(duration: 0.38), value: isStruck)
            }
            .opacity(isStruck ? 0.55 : 1)
            .animation(.easeOut(duration: 0.5).delay(0.25), value: isStruck)
    }

    private func play() {
        struck = 0
        drifting = true
        timeline?.cancel()
        timeline = Task {
            try? await Task.sleep(for: .seconds(0.7))
            for i in 1...pills.count {
                guard !Task.isCancelled else { return }
                struck = i
                Haptics.soft()
                try? await Task.sleep(for: .seconds(0.22))
            }
        }
    }

    /// A hand-drawn strike: slightly uphill, like a quick pen stroke.
    private struct StrikeLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.08))
            return path
        }
    }
}

// MARK: - Scene 2: the plate, and what lands on it

/// A plain plate inside the pastel ring. Three adds fly in and dock on the
/// rim, and the segment under each one lights up. Nothing leaves.
struct PlateScene: View {
    @State private var landed: Set<Compound> = []
    @State private var timeline: Task<Void, Never>?

    private let ringSize: CGFloat = 210
    private let lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            TrioRing(compounds: landed, size: ringSize, lineWidth: lineWidth, pastelTrack: true)

            Circle()
                .fill(Palette.card)
                .frame(width: ringSize - 56, height: ringSize - 56)
                .overlay(
                    Circle().strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: Color(hex: "2E3A54").opacity(0.05), radius: 4, y: 2)
                .shadow(color: Color(hex: "2E3A54").opacity(0.08), radius: 22, y: 10)
                .overlay(
                    Text("your meal")
                        .font(.editorial(20))
                        .foregroundStyle(Palette.inkSoft)
                )

            ForEach(Compound.allCases) { compound in
                badge(compound)
            }
        }
        .frame(width: ringSize + 80, height: ringSize + 80)
        .onAppear(perform: play)
        .onDisappear { timeline?.cancel() }
        .accessibilityElement()
        .accessibilityLabel("Protein, fibre and healthy fats land on your meal.")
    }

    /// One add, docked on the rim over its own segment. Before it lands it
    /// waits further out, small and faint.
    private func badge(_ compound: Compound) -> some View {
        let isHere = landed.contains(compound)
        let angle = OnboardingGeometry.segmentAngle(compound)
        let radius: CGFloat = isHere ? ringSize / 2 : ringSize / 2 + 70
        return ZStack {
            Circle()
                .fill(compound.tint)
                .overlay(Circle().strokeBorder(Palette.card, lineWidth: 3))
                .shadow(color: compound.color.opacity(0.35), radius: 10, y: 4)
            Text(compound.emoji)
                .font(.system(size: 21))
        }
        .frame(width: 48, height: 48)
        .scaleEffect(isHere ? 1 : 0.5)
        .opacity(isHere ? 1 : 0)
        .offset(x: radius * cos(angle), y: radius * sin(angle))
        .animation(.spring(duration: 0.6, bounce: 0.34), value: isHere)
    }

    private func play() {
        landed = []
        timeline?.cancel()
        timeline = Task {
            try? await Task.sleep(for: .seconds(0.6))
            for compound in Compound.allCases {
                guard !Task.isCancelled else { return }
                landed.insert(compound)
                Haptics.soft()
                try? await Task.sleep(for: .seconds(0.55))
            }
        }
    }
}

// MARK: - Scene 3: the trio, explained on the ring

/// The ring lights one builder at a time. As each segment comes on, an
/// arrow draws itself from the builder's name to that segment, and one
/// line about what it does appears underneath.
struct TrioExplainerScene: View {
    @State private var lit: Set<Compound> = []
    @State private var arrows: Set<Compound> = []
    @State private var timeline: Task<Void, Never>?

    private let ringSize: CGFloat = 172
    private let lineWidth: CGFloat = 16

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                TrioRing(compounds: lit, size: ringSize, lineWidth: lineWidth, pastelTrack: true)
                ForEach(Compound.allCases) { compound in
                    arrow(compound)
                    chip(compound)
                }
            }
            .frame(width: 340, height: 300)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Compound.allCases) { compound in
                    benefitRow(compound)
                }
            }
        }
        .onAppear(perform: play)
        .onDisappear { timeline?.cancel() }
    }

    /// Where each name sits around the ring: protein up right, fibre
    /// below, healthy fats up left. Read by the arrows as their start.
    private func chipOffset(_ compound: Compound) -> CGPoint {
        switch compound {
        case .protein: CGPoint(x: 122, y: -112)
        case .fibre: CGPoint(x: 86, y: 142)
        case .fats: CGPoint(x: -114, y: -112)
        }
    }

    /// Half the chip's width, so the arrow can set off from its edge
    /// rather than from under it.
    private func chipHalfWidth(_ compound: Compound) -> CGFloat {
        switch compound {
        case .protein: 40
        case .fibre: 32
        case .fats: 56
        }
    }

    /// Where the arrow leaves the chip: on the chip's rounded edge, on the
    /// side facing the ring, plus a little air.
    private func arrowStart(_ compound: Compound) -> CGPoint {
        let centre = chipOffset(compound)
        let target = ringPoint(compound)
        let dx = target.x - centre.x, dy = target.y - centre.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length, uy = dy / length
        // Treat the capsule as an ellipse and step out to its edge.
        let a = chipHalfWidth(compound), b: CGFloat = 17
        let edge = 1 / sqrt((ux / a) * (ux / a) + (uy / b) * (uy / b)) + 5
        return CGPoint(x: centre.x + ux * edge, y: centre.y + uy * edge)
    }

    /// Just outside the middle of the builder's own segment.
    private func ringPoint(_ compound: Compound) -> CGPoint {
        let angle = OnboardingGeometry.segmentAngle(compound)
        let radius = ringSize / 2 + lineWidth / 2 + 9
        return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    private func chip(_ compound: Compound) -> some View {
        let isOn = lit.contains(compound)
        let offset = chipOffset(compound)
        return Text(compound.label)
            .font(.display(14, weight: .semibold))
            .foregroundStyle(isOn ? compound.color : Palette.inkSoft)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isOn ? compound.tint : Palette.card)
                    .overlay(Capsule().strokeBorder(isOn ? compound.color.opacity(0.3) : Palette.hairline, lineWidth: 1))
                    .shadow(color: Color(hex: "2E3A54").opacity(isOn ? 0.08 : 0.04), radius: 10, y: 5)
            )
            .scaleEffect(isOn ? 1 : 0.92)
            .offset(x: offset.x, y: offset.y)
            .animation(.spring(duration: 0.45, bounce: 0.3), value: isOn)
    }

    /// Which way each arrow bellies. Fats and protein mirror each other,
    /// bulging away from the ring like the two arms of a parabola; fibre
    /// dips down before it turns up into the bottom of the ring.
    private func bow(_ compound: Compound) -> CGFloat {
        switch compound {
        case .protein: -14
        case .fibre: -24
        case .fats: 14
        }
    }

    /// Draws from the chip to the segment; the head arrives last.
    private func arrow(_ compound: Compound) -> some View {
        let drawn = arrows.contains(compound)
        return DrawnArrow(from: arrowStart(compound), to: ringPoint(compound), bow: bow(compound))
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(compound.color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .animation(.easeOut(duration: 0.5), value: drawn)
    }

    private func benefitRow(_ compound: Compound) -> some View {
        let isOn = lit.contains(compound)
        return HStack(spacing: 12) {
            Circle()
                .fill(compound.color)
                .frame(width: 9, height: 9)
            Text(compound.whisper.prefix(1).uppercased() + compound.whisper.dropFirst() + ".")
                .font(.display(15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .opacity(isOn ? 1 : 0)
        .offset(y: isOn ? 0 : 10)
        .animation(.spring(duration: 0.55, bounce: 0.2), value: isOn)
    }

    private func play() {
        lit = []
        arrows = []
        timeline?.cancel()
        timeline = Task {
            try? await Task.sleep(for: .seconds(0.5))
            for compound in Compound.allCases {
                guard !Task.isCancelled else { return }
                lit.insert(compound)
                Haptics.soft()
                try? await Task.sleep(for: .seconds(0.12))
                guard !Task.isCancelled else { return }
                arrows.insert(compound)
                try? await Task.sleep(for: .seconds(0.85))
            }
        }
    }
}

/// A short curved arrow that can be trimmed from nothing to whole, so it
/// looks drawn by hand: the bowed line first, then the two head strokes.
/// Points are relative to the centre of the frame it's drawn in.
struct DrawnArrow: Shape {
    var from: CGPoint
    var to: CGPoint
    /// Sideways bulge at the middle; zero is a straight line.
    var bow: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let a = CGPoint(x: centre.x + from.x, y: centre.y + from.y)
        let b = CGPoint(x: centre.x + to.x, y: centre.y + to.y)
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let control = CGPoint(x: (a.x + b.x) / 2 + normal.x * bow, y: (a.y + b.y) / 2 + normal.y * bow)

        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)

        // Head: two strokes back from the tip along the curve's end tangent.
        let tangent = atan2(b.y - control.y, b.x - control.x)
        let headLength: CGFloat = 8
        for spread in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8] {
            let angle = tangent + spread
            path.move(to: b)
            path.addLine(to: CGPoint(x: b.x + cos(angle) * headLength, y: b.y + sin(angle) * headLength))
        }
        return path
    }
}

// MARK: - Scene 4: the demo video

/// The walkthrough clip, looping silently inside a phone. The frame is
/// drawn, not a photo, so it sizes to whatever room the page has and the
/// whole clip is always in view: the video fits inside the screen area
/// rather than filling it.
struct DemoVideoScene: View {
    /// The clip's own proportions, so the drawn phone is built around it
    /// and the screen holds the clip edge to edge, no bars, no slivers.
    private let screenAspect: CGFloat = 940 / 1920

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The phone is raised into view the way a hand lifts one to snap a
    /// plate: from low and tilted back, up into the centre.
    @State private var raised = false

    private var clipURL: URL? {
        Bundle.main.url(forResource: "onboarding-demo", withExtension: "mp4")
    }

    var body: some View {
        PhoneFrame(screenAspect: screenAspect) {
            if let clipURL {
                LoopingVideo(url: clipURL)
            } else {
                // Only if the clip ever goes missing from the bundle: the
                // phone still stands, dark, so the page keeps its shape.
                Color.black
            }
        }
        .accessibilityLabel("A short clip of snapping a plate and adding to it")
        .rotation3DEffect(
            .degrees(raised || reduceMotion ? 0 : 38),
            axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55
        )
        .scaleEffect(raised || reduceMotion ? 1 : 0.82, anchor: .bottom)
        .offset(y: raised || reduceMotion ? 0 : 260)
        .opacity(raised ? 1 : 0)
        .onAppear {
            raised = false
            withAnimation(.spring(duration: 1.05, bounce: 0.18).delay(0.25)) {
                raised = true
            }
        }
    }
}

/// A drawn iPhone built outward from its screen: the screen takes the
/// clip's exact proportions, the bezel wraps it, and the island sits over
/// the top of the clip (which carries the recording's own island, so the
/// drawn one covers it). Every measure is a fraction of the width, so it
/// looks the same at any size the page gives it.
private struct PhoneFrame<Screen: View>: View {
    var screenAspect: CGFloat
    @ViewBuilder var screen: () -> Screen

    /// Bezel and corner, as fractions of the phone's outer width.
    private let bezelFraction: CGFloat = 0.03
    private let screenCornerFraction: CGFloat = 0.135

    /// The outer proportions that give the screen exactly `screenAspect`
    /// once the bezel is taken off all four sides.
    private var outerAspect: CGFloat {
        1 / ((1 - 2 * bezelFraction) / screenAspect + 2 * bezelFraction)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let bezel = width * bezelFraction
            let screenCorner = width * screenCornerFraction
            let body = RoundedRectangle(cornerRadius: screenCorner + bezel, style: .continuous)
            ZStack(alignment: .top) {
                body
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "23262E"), Color(hex: "0F1116")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(body.strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: Color(hex: "2E3A54").opacity(0.28), radius: 28, y: 14)

                screen()
                    .frame(width: width - 2 * bezel, height: (width - 2 * bezel) / screenAspect)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))
                    .padding(bezel)

                // The island, the one mark that says "this is a phone". Sized
                // to sit over the recording's own.
                Capsule()
                    .fill(.black)
                    .frame(width: width * 0.31, height: width * 0.08)
                    .padding(.top, bezel + width * 0.022)
            }
        }
        .aspectRatio(outerAspect, contentMode: .fit)
        .frame(maxWidth: 280)
    }
}

/// An `AVPlayerLayer` that loops one clip, muted, fitting the whole frame
/// inside its bounds. Pauses when it leaves the screen and picks up again
/// when the app comes back to the front.
private struct LoopingVideo: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        private var foregroundObserver: NSObjectProtocol?

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            player = AVQueuePlayer(items: [item])
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: item)
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.player.play() }
        }

        deinit {
            if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
            player.pause()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> PlayerView {
        // A silent clip must not silence someone's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .moviePlayback)
        let view = PlayerView()
        view.playerLayer.player = context.coordinator.player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        context.coordinator.player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
    }
}

// MARK: - Scene 5: all set

/// The ring, then its three segments lighting one after another. The
/// payoff picture, no ornament.
struct AllSetScene: View {
    @State private var shown = false
    @State private var lit: Set<Compound> = []
    @State private var timeline: Task<Void, Never>?

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.roseTint.opacity(0.7))
                .frame(width: 230, height: 230)
                .blur(radius: 40)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
            TrioRing(compounds: lit, size: 150, lineWidth: 14, pastelTrack: true)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
        }
        .frame(height: 260)
        .animation(.spring(duration: 0.6, bounce: 0.22), value: shown)
        .onAppear(perform: play)
        .onDisappear { timeline?.cancel() }
        .accessibilityHidden(true)
    }

    private func play() {
        shown = false
        lit = []
        timeline?.cancel()
        timeline = Task {
            try? await Task.sleep(for: .seconds(0.15))
            shown = true
            try? await Task.sleep(for: .seconds(0.5))
            for compound in Compound.allCases {
                guard !Task.isCancelled else { return }
                lit.insert(compound)
                Haptics.soft()
                try? await Task.sleep(for: .seconds(0.4))
            }
        }
    }
}

// MARK: - Shared geometry

enum OnboardingGeometry {
    /// The middle of each builder's ring segment, in SwiftUI's clockwise
    /// radians from 3 o'clock. `TrioRing` starts protein at 12 o'clock.
    static func segmentAngle(_ compound: Compound) -> CGFloat {
        switch compound {
        case .protein: -.pi / 6
        case .fibre: .pi / 2
        case .fats: .pi * 7 / 6
        }
    }
}
