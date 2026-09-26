//
//  Shiphaton_AppApp.swift
//  Shiphaton App
//
//  Created by Burak Eren Demir on 31.08.2026.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck

/// App Attest where the device offers it, DeviceCheck where it doesn't
/// (an iPhone app running on an Apple silicon Mac, for one). Without the
/// fallback the provider comes back nil there and every AI call fails
/// App Check silently, leaving the app on its offline copy for no visible
/// reason.
private final class AttestOrDeviceCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app) ?? DeviceCheckProvider(app: app)
    }
}

@main
struct Shiphaton_AppApp: App {
    init() {
        // Must be set before `FirebaseApp.configure()`. App Attest proves a
        // request came from a genuine, untampered build of this app — no
        // sign-in involved. Simulators and DEBUG builds can't do App
        // Attest, so they fall back to a debug token instead (registered
        // once in the Firebase console under App Check).
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AttestOrDeviceCheckFactory())
        #endif
        FirebaseApp.configure()
        // Before any view can ask about entitlements. Keyed on the same
        // Keychain id the AI gate is keyed on, so a reinstall restores onto
        // the customer it already had.
        SubscriptionStore.configure()
        // So "you're offline" can be said before a call, not after a
        // timeout.
        NetworkMonitor.shared.start()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meal.self,
            EnergyCheck.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Palette.rose)
                // v1 ships light only. Set here so sheets and the tab bar's
                // glass follow too, whatever the phone is set to.
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
    }
}
