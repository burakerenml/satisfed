//
//  RootView.swift
//  Shiphaton App
//
//  The one switch above everything: the intro until it has been seen
//  through, the app after. Cross-fades between the two, and the You tab
//  can flip it back to replay the intro.
//

import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ProfileKey.didOnboard) private var didOnboard = false

    var body: some View {
        ZStack {
            if didOnboard {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView(startAt: Self.initialStep) {
                    didOnboard = true
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: didOnboard)
        .dismissesKeyboardOnTap()
        // Starts the entitlement stream and asks the server where we
        // stand. Nothing gates on the answer, the app opens the same either
        // way, so a slow reply costs nobody a screen.
        .task { SubscriptionStore.shared.start() }
        .onChange(of: scenePhase) { _, phase in
            // A subscription can change while the app is away: bought on
            // another device, cancelled in Settings, lapsed overnight.
            if phase == .active {
                Task { await SubscriptionStore.shared.refreshGateState() }
            }
        }
        #if DEBUG
        .onAppear(perform: Self.applyDebugLaunchArguments)
        #endif
    }

    /// "-uionboarding [hook|promise|trio|snap|name|goal|diet|avoid|done]"
    /// opens the intro on that page.
    private static var initialStep: OnboardingView.Step {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uionboarding"), index + 1 < arguments.count {
            let names = ["hook", "promise", "trio", "snap", "name", "goal", "diet", "avoid", "done"]
            if let raw = names.firstIndex(of: arguments[index + 1]), let step = OnboardingView.Step(rawValue: raw) {
                return step
            }
        }
        #endif
        return .hook
    }

    #if DEBUG
    /// Screenshot hooks: "-uionboarding" forces the intro; any other
    /// "-ui…" flag skips it, so the existing tab and sheet hooks still
    /// land where they point.
    private static func applyDebugLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uionboarding") {
            UserDefaults.standard.set(false, forKey: ProfileKey.didOnboard)
        } else if arguments.contains(where: { $0.hasPrefix("-ui") }) {
            UserDefaults.standard.set(true, forKey: ProfileKey.didOnboard)
            // Skipping the intro also skips its questions, and the recipe
            // maker keeps its built-in plates to itself until one of them
            // is answered. Screenshots want the app as someone who
            // answered sees it, so stand in the answer that rules nothing
            // out. A seeded profile later in the launch still wins.
            if Diet(rawValue: UserDefaults.standard.string(forKey: ProfileKey.diet) ?? "") == nil {
                UserDefaults.standard.set(Diet.everything.rawValue, forKey: ProfileKey.diet)
            }
        }
    }
    #endif
}
