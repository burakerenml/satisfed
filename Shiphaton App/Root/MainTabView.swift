//
//  MainTabView.swift
//  Shiphaton App
//
//  Root: iOS 26-native floating bar — a compact liquid-glass capsule with
//  the tabs, and the camera as a detached rose glass circle beside it, the
//  way Apple pairs tab bar + search in its own apps.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection: AppTab = MainTabView.initialTab
    @State private var showLogFlow = false
    #if DEBUG
    @State private var showDebugDetail = false
    private static let debugMeal = Meal(
        name: "Instant noodles",
        emoji: "\u{1F35C}",
        compounds: [.protein, .fibre, .fats],
        boosts: ["a sprinkle of tofu cubes", "a handful of edamame", "Olive oil"]
    )
    #endif

    // One namespace for the whole bar: the selection pill slides the full
    // width, passing behind the camera disc.
    @Namespace private var indicator

    enum AppTab: String, CaseIterable, Identifiable {
        case home, progress, you

        var id: String { rawValue }

        var label: String {
            switch self {
            case .home: "Home"
            case .progress: "Progress"
            case .you: "You"
            }
        }

        var icon: String {
            switch self {
            case .home: "house"
            // A leaf, not a bar chart: this page tracks growth, not scores.
            case .progress: "leaf"
            case .you: "heart"
            }
        }

        var iconFilled: String {
            switch self {
            case .home: "house.fill"
            case .progress: "leaf.fill"
            case .you: "heart.fill"
            }
        }
    }

    var body: some View {
        // The one place the window is measured. Everything below spaces
        // itself from this, so the layout is the device's rather than one
        // phone's numbers hard-coded.
        // NOTE: never read UIApplication window insets inside `body` —
        // doing so froze all SwiftUI updates after first render.
        GeometryReader { proxy in
            let layout = Layout(size: proxy.size, safeBottom: proxy.safeAreaInsets.bottom)
            ZStack(alignment: .bottom) {
                Group {
                    switch selection {
                    case .home: HomeView(showLogFlow: $showLogFlow)
                    case .progress: ProgressTabView()
                    case .you: YouView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 14)),
                    removal: .opacity
                ))

                tabBar(edgePadding: layout.tabBarEdgePadding)
            }
            .environment(\.layout, layout)
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showLogFlow) {
            LogFlowView()
                .presentationCornerRadius(32)
        }
        #if DEBUG
        .bottomCard(isPresented: $showDebugDetail) {
            MealDetailView(meal: Self.debugMeal)
        }
        #endif
        #if DEBUG
        .onAppear(perform: applyDebugLaunchArguments)
        #endif
    }

    /// "-uitab" is resolved at state init (not onAppear) so screenshots land
    /// directly on the requested tab with no flash of Home.
    private static var initialTab: AppTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uitab"), index + 1 < arguments.count,
           let tab = AppTab(rawValue: arguments[index + 1]) {
            return tab
        }
        #endif
        return .home
    }

    #if DEBUG
    /// Screenshot/UI-test hooks: launch with "-uitab progress", "-uilog",
    /// or "-uidetail" (a sample plate's detail card over Home).
    private func applyDebugLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uidetail") {
            showDebugDetail = true
        }
        if arguments.contains("-uilog") {
            showLogFlow = true
        }
        // Simulates a tab tap 1.5s after launch (simctl can't tap): exercises
        // the same withAnimation path as tabButton, for screenshot-verifying
        // that runtime tab switching works.
        if arguments.contains("-uiswitch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring(duration: 0.42, bounce: 0.22)) {
                    selection = .you
                }
            }
        }
    }
    #endif

    // MARK: - Tab bar

    /// iOS 26 native pattern: a compact glass capsule holding the tabs, and
    /// the camera as a detached tinted glass circle beside it — the same
    /// arrangement Apple uses for tab bar + search in its own apps.
    /// One `GlassEffectContainer` so the two shapes share the liquid glass.
    private func tabBar(edgePadding: CGFloat) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    tabButton(.home)
                    tabButton(.progress)
                    tabButton(.you)
                }
                // Side room so the selection pill stays inside the capsule's
                // own curve.
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                // A card-toned tint keeps the glass but lifts it out of the
                // fog; the hairline gives the capsule a crisp edge.
                .glassEffect(.regular.tint(Palette.card.opacity(0.55)), in: Capsule())
                .overlay(Capsule().stroke(Palette.hairline.opacity(0.7), lineWidth: 1))

                cameraButton
            }
        }
        .shadow(color: Color(hex: "2E3A54").opacity(0.08), radius: 16, y: 8)
        // Cap the bar so the three slots keep the same thumb-sized rhythm
        // they had as four of a 400pt bar, instead of stretching wider.
        .frame(maxWidth: 330)
        .padding(.horizontal, 20)
        .padding(.bottom, edgePadding)
        .frame(maxWidth: .infinity)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        return Button {
            guard selection != tab else { return }
            Haptics.soft()
            withAnimation(.spring(duration: 0.42, bounce: 0.22)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isOn ? tab.iconFilled : tab.icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 22)
                Text(tab.label)
                    .font(.display(10, weight: .semibold))
            }
            .foregroundStyle(isOn ? Palette.roseDeep : Palette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if isOn {
                    Capsule()
                        .fill(Palette.roseTint.opacity(0.9))
                        // Inset so the pill never crowds the capsule's own
                        // curve — a soft pill around the item, not a blob.
                        .padding(.horizontal, 4)
                        .matchedGeometryEffect(id: "tab", in: indicator)
                }
            }
            // Make the whole slot tappable, not just the drawn pixels.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The camera: a tinted, interactive liquid-glass circle detached from
    /// the tab capsule. It goes straight to the viewfinder, the recipe
    /// builder and craving translator already have their own doorways on
    /// Home, so a menu in between was only a step to tap past.
    private var cameraButton: some View {
        Button {
            Haptics.tap()
            showLogFlow = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: cameraDiscSize, height: cameraDiscSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Palette.rose).interactive(), in: Circle())
        .accessibilityLabel("Snap a meal")
    }

    /// Matched to the capsule's height so the two glass shapes sit on one line.
    private var cameraDiscSize: CGFloat { 60 }
}
