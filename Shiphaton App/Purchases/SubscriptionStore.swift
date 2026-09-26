//
//  SubscriptionStore.swift
//  Shiphaton App
//
//  What the app knows about whether this person is subscribed, and whether
//  their one free loop is still in hand.
//
//  Two sources, on purpose. RevenueCat answers locally and instantly, which
//  is what unlocks the app the moment a purchase goes through. The server
//  answers authoritatively, which is what actually guards the AI budget.
//  The app trusts the local answer for showing things and the server for
//  spending things, so a tampered client can only lie to itself.
//

import FirebaseFunctions
import Foundation
import RevenueCat

@MainActor
@Observable
final class SubscriptionStore {

    static let shared = SubscriptionStore()

    /// The entitlement configured in the RevenueCat dashboard.
    static let entitlementID = "Premium"

    /// Public API key from the RevenueCat dashboard. Swap the `test_` key
    /// for the live `appl_` one before shipping; it's a publishable key, so
    /// it belongs in the binary.
    private static let apiKey = "appl_HyvfJziqZJwsljSgzkOkHkvRvXp"

    // MARK: - State

    /// Subscribed, according to RevenueCat on this device.
    private var localActive = false

    /// Subscribed, according to the server's own read of RevenueCat. A
    /// definite yes only: "couldn't check" is tracked separately, so a bad
    /// network never dresses a free account up as Premium.
    private var serverPro = false

    /// The server couldn't reach RevenueCat. Its gate fails open in that
    /// case, and so does the UI: no paywall, but no "Premium" either.
    private(set) var gateUnsure = false

    /// Subscribed by either account. Local answers first, the moment a
    /// purchase goes through; the server confirms it a beat later.
    var isSubscribed: Bool { localActive || serverPro }

    /// The server says the free loop has been spent. Only meaningful while
    /// `isSubscribed` is false.
    private(set) var freeLoopSpent = false

    /// False until the first answer lands. Nothing should offer or refuse
    /// anything before that, or a cold launch flashes a paywall at someone
    /// who has been paying for a year.
    private(set) var hasAnswer = false

    /// True when there's nothing left to give away: not subscribed, the
    /// server is sure of it, and the free loop is gone. The one flag the
    /// UI needs.
    var needsSubscription: Bool { hasAnswer && !isSubscribed && !gateUnsure && freeLoopSpent }

    /// RevenueCat on this device says subscribed, but the server hasn't
    /// agreed yet. While that's true every AI call should tell the gate to
    /// go and look at RevenueCat rather than trust its mirror: a purchase
    /// can be seconds old, and the mirror was stamped "free" moments
    /// before it by the very call that was refused.
    var wantsFreshGate: Bool { localActive && !serverPro }

    private var streamTask: Task<Void, Never>?
    private var functions = Functions.functions()

    private init() {}

    // MARK: - Launch

    /// Configures RevenueCat and starts listening. Called once, from the
    /// app's init, before any view can ask about entitlements.
    nonisolated static func configure() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .info
        #endif
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: apiKey)
                // The Keychain id, so a reinstall restores onto the same
                // customer instead of creating an anonymous second one.
                .with(appUserID: DeviceIdentity.current)
                .build()
        )
    }

    /// Starts the customer info stream and asks the server where we stand.
    func start() {
        guard streamTask == nil, Purchases.isConfigured else { return }
        streamTask = Task { [weak self] in
            // Fires on launch, after a purchase, after a restore, and when
            // a subscription lapses. One place for every entitlement change.
            for await info in Purchases.shared.customerInfoStream {
                guard let self else { return }
                let active = info.entitlements[Self.entitlementID]?.isActive == true
                let changed = active != self.localActive
                self.localActive = active
                self.hasAnswer = true
                // A change here means the server's mirror is about to move
                // too, so go and read it rather than wait for the webhook.
                // A purchase asks for a fresh look: the mirror was stamped
                // "free" moments ago by the very call that was refused,
                // and a plain read would only repeat it.
                if changed { await self.refreshGateState(fresh: active) }
            }
        }
        Task { await refreshGateState() }
    }

    // MARK: - The server's answer

    /// Asks the gate what it would say. Cheap, and it spends nothing: it's
    /// how the app knows to offer the paywall on the summary screen rather
    /// than on the next thing the person tries.
    ///
    /// `fresh` is for right after a purchase or restore: the server's
    /// mirror of RevenueCat can lag a purchase by hours until the webhook
    /// lands, and this tells it to go and look rather than trust the mirror.
    func refreshGateState(fresh: Bool = false) async {
        do {
            var body: [String: Any] = ["appUserID": DeviceIdentity.current]
            if fresh { body["fresh"] = true }
            let result = try await functions
                .httpsCallable("entitlementStatus")
                .call(body)
            guard let payload = result.data as? [String: Any] else { return }
            // "pro" is a definite yes, "free" a definite no, "unknown" means
            // the server couldn't reach RevenueCat and is failing open.
            let proState = payload["proState"] as? String
                ?? (payload["pro"] as? Bool == true ? "pro" : "free")
            serverPro = proState == "pro"
            gateUnsure = proState == "unknown"
            freeLoopSpent = (payload["freeLoop"] as? String) == "used"
            hasAnswer = true
        } catch {
            // Offline or App Check still warming up. Say nothing rather
            // than assume the worst about someone who may well have paid.
            hasAnswer = true
        }
    }

    // MARK: - Purchases

    /// Restore, for the "already subscribed" path on a new phone. The
    /// RevenueCat paywall has its own restore button; this backs the You
    /// tab's row.
    @discardableResult
    func restore() async -> Bool {
        guard Purchases.isConfigured else { return false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            localActive = info.entitlements[Self.entitlementID]?.isActive == true
            await refreshGateState(fresh: true)
            return isSubscribed
        } catch {
            return false
        }
    }

    /// Called by the paywall host once a purchase or restore completes, so
    /// the local flag and the server's view agree before anything retries.
    func acknowledge(_ info: CustomerInfo) async {
        localActive = info.entitlements[Self.entitlementID]?.isActive == true
        hasAnswer = true
        await refreshGateState(fresh: true)
    }
}
