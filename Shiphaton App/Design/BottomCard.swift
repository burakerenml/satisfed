//
//  BottomCard.swift
//  Shiphaton App
//
//  The app's own short sheet. iOS 26 lifts every partial-height system
//  sheet off the bottom edge and rounds all four corners, which left a
//  strip of page showing under each of our small cards, and there is no
//  public switch for it. So the small cards are drawn here instead: a
//  clear full-screen cover holding a dim and a card that runs flush to
//  the bottom of the screen, with its own slide, drag, and tap-away.
//

import SwiftUI

extension View {
    /// Present `content` as a card that rises from the bottom edge. Used
    /// where a system `.sheet` at a short detent used to be.
    func bottomCard<CardContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> CardContent
    ) -> some View {
        modifier(BottomCardModifier(isPresented: isPresented, content: content))
    }

    /// Item-driven twin of `bottomCard(isPresented:)`. The last item is
    /// kept until the card has slid away, so it doesn't blank mid-exit.
    func bottomCard<Item: Identifiable, CardContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> CardContent
    ) -> some View {
        modifier(BottomCardItemModifier(item: item, content: content))
    }
}

/// Closes the card the view sits in. Content inside a bottom card calls
/// this rather than `dismiss`: `dismiss` would drop the whole cover, dim
/// and all, in one system slide, instead of the card's own exit.
struct DismissCardAction {
    fileprivate var run: () -> Void = {}
    func callAsFunction() { run() }
}

private struct DismissCardKey: EnvironmentKey {
    static let defaultValue = DismissCardAction()
}

extension EnvironmentValues {
    var dismissCard: DismissCardAction {
        get { self[DismissCardKey.self] }
        set { self[DismissCardKey.self] = newValue }
    }
}

// MARK: - Modifiers

private struct BottomCardModifier<CardContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var content: () -> CardContent

    /// The cover's own switch. It only ever flips without animation: the
    /// system's slide is for the whole cover, dim included, and the card
    /// runs its own entrance and exit inside.
    @State private var coverShown = false

    func body(content base: Content) -> some View {
        base
            .onChange(of: isPresented, initial: true) { _, wanted in
                if wanted, !coverShown {
                    withoutAnimation { coverShown = true }
                }
            }
            .fullScreenCover(isPresented: $coverShown) {
                BottomCardHost(isPresented: $isPresented, content: content) {
                    withoutAnimation { coverShown = false }
                }
                .presentationBackground(.clear)
            }
    }
}

private struct BottomCardItemModifier<Item: Identifiable, CardContent: View>: ViewModifier {
    @Binding var item: Item?
    var content: (Item) -> CardContent

    /// The item the card is showing, kept through the exit animation
    /// after `item` has already gone back to nil.
    @State private var current: Item?

    func body(content base: Content) -> some View {
        // Read here, in the body, not only inside the card's closure: the
        // cover is presented from a copy of this modifier, and a closure
        // that reads the state lazily saw nil there and never refreshed,
        // so the card came up empty. Capturing the value makes the body
        // depend on it and hands the cover a closure with the item baked in.
        let showing = current
        return base
            .onChange(of: item?.id, initial: true) { _, _ in
                if let item { current = item }
            }
            .bottomCard(isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            )) {
                if let showing { content(showing) }
            }
    }
}

private let cardRadius: CGFloat = 32
private let cardDim = 0.22

private func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

// MARK: - Host

/// What lives inside the clear cover: the dim, the card, and the gestures
/// that close them.
private struct BottomCardHost<CardContent: View>: View {
    @Binding var isPresented: Bool
    var content: () -> CardContent
    /// Called once the card has slid away, so the cover can go too.
    var onGone: () -> Void

    @State private var shown = false
    @State private var leaving = false
    @State private var drag: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(shown ? cardDim : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)

                if shown {
                    card(cap: proxy.size.height * 0.9)
                        .offset(y: drag)
                        // By the whole window, not the card's own height:
                        // the colour runs on past the card's frame into the
                        // safe area, and a shorter slide would leave that
                        // strip behind for a frame.
                        .transition(.offset(y: proxy.size.height + proxy.safeAreaInsets.bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .environment(\.dismissCard, DismissCardAction(run: close))
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.16)) { shown = true }
        }
        .onChange(of: isPresented) { _, wanted in
            if !wanted { leave() }
        }
    }

    private func card(cap: CGFloat) -> some View {
        let fits = contentHeight <= cap
        return Group {
            if fits {
                measured
            } else {
                ScrollView { measured }
                    .frame(height: cap)
            }
        }
        .frame(maxWidth: .infinity)
        // The card's colour runs on under the home indicator: the system
        // sheet stopped short of it, and that gap is the whole complaint.
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: cardRadius, topTrailingRadius: cardRadius,
                style: .continuous
            )
            .fill(Palette.canvas)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Palette.inkSoft.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .allowsHitTesting(false)
        }
        // Content that fits drags anywhere; content that scrolls only
        // drags from its grabber, so the list keeps the rest.
        .gesture(dragToClose, isEnabled: fits)
        .overlay(alignment: .top) {
            if !fits {
                Color.clear
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .gesture(dragToClose)
            }
        }
        .accessibilityAction(.escape, close)
    }

    private var measured: some View {
        content()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }

    private var dragToClose: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let y = value.translation.height
                // Pulling up gives a little, not a lot.
                drag = y < 0 ? y * 0.15 : y
            }
            .onEnded { value in
                let y = value.translation.height
                if y > 110 || value.predictedEndTranslation.height > 240 {
                    close()
                } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { drag = 0 }
                }
            }
    }

    private func close() {
        guard !leaving else { return }
        isPresented = false
    }

    private func leave() {
        guard !leaving else { return }
        leaving = true
        withAnimation(.easeIn(duration: 0.24)) {
            shown = false
        } completion: {
            onGone()
        }
    }
}
