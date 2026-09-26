//
//  PaywallModel.swift
//  Shiphaton App
//
//  Everything the paywall screen needs to know, fetched from RevenueCat
//  and shaped for display: the two plans with real store prices, whether
//  this person still qualifies for the free trial, the saving of yearly
//  over monthly, and the state of a purchase in flight.
//
//  The screen itself stays dumb. It reads `plans`, `selected`, `phase`,
//  and calls `buy()` / `restore()`; nothing about StoreKit leaks past here.
//

import Foundation
import RevenueCat

/// One row in the plan picker, already worded for the screen. Everything
/// on it comes from the store through RevenueCat: the product's own name,
/// its price, its billing period, its trial.
struct PaywallPlan: Identifiable, Equatable {
    enum Term: Equatable {
        case year, month, week, day
        case lifetime

        /// "year" in "$X a year".
        var word: String {
            switch self {
            case .year: "year"
            case .month: "month"
            case .week: "week"
            case .day: "day"
            case .lifetime: "once"
            }
        }

        /// The rate suffix a store writes next to the price: "/yr", "/mo".
        /// Empty for a one-off, which has no rate at all.
        var rate: String {
            switch self {
            case .year: "/yr"
            case .month: "/mo"
            case .week: "/wk"
            case .day: "/day"
            case .lifetime: ""
            }
        }

        /// Fallback name when the store gives the product no title.
        var name: String {
            switch self {
            case .year: "Yearly"
            case .month: "Monthly"
            case .week: "Weekly"
            case .day: "Daily"
            case .lifetime: "Lifetime"
            }
        }

        /// Longest period first, so the best deal leads the list.
        var rank: Int {
            switch self {
            case .lifetime: 0
            case .year: 1
            case .month: 2
            case .week: 3
            case .day: 4
            }
        }
    }

    let id: String
    let term: Term
    let package: Package

    /// The plan's name on the row: its period, plainly ("Yearly").
    let title: String
    /// "$39.99" for the term, straight from the store.
    let price: String
    /// Percentage saved over the dearest plan per year, in the same
    /// currency. Nil when it isn't a saving worth mentioning.
    let savingPercent: Int?
    /// The introductory free trial, if the product carries one and this
    /// person hasn't used one before.
    let trial: Trial?

    struct Trial: Equatable {
        let value: Int
        let unit: SubscriptionPeriod.Unit

        /// "7 days", "1 month"
        var long: String {
            "\(value) \(unitWord)\(value == 1 ? "" : "s")"
        }

        private var unitWord: String {
            switch unit {
            case .day: "day"
            case .week: "week"
            case .month: "month"
            case .year: "year"
            @unknown default: "day"
            }
        }
    }

    /// "a year", "a month", "once".
    var perTerm: String { term == .lifetime ? "once" : "a \(term.word)" }

    static func == (lhs: PaywallPlan, rhs: PaywallPlan) -> Bool { lhs.id == rhs.id }
}

@MainActor
@Observable
final class PaywallModel {

    enum Phase: Equatable {
        /// Fetching offerings. The plan cards show placeholders.
        case loading
        /// Plans on screen, nothing in flight.
        case ready
        /// A purchase or restore is talking to the store.
        case working
        /// The offerings couldn't be loaded at all. Retry is offered.
        case unavailable
    }

    private(set) var phase: Phase = .loading
    private(set) var plans: [PaywallPlan] = []
    private(set) var selectedID: String?

    /// A short, human line under the button when something didn't go
    /// through: a failed load, a restore that found nothing. Cleared on the
    /// next action. Never shown for a cancelled purchase, which is not an
    /// error, just a no.
    private(set) var notice: String?

    /// Copy the dashboard may override per offering, so wording can be
    /// tuned (and A/B tested through Offerings) without a release. Keys:
    /// `headline`, `subheadline`, `cta`. Absent keys fall back to the
    /// screen's own words.
    private(set) var remoteCopy: [String: String] = [:]

    var selected: PaywallPlan? { plans.first { $0.id == selectedID } }

    /// Which placement this is, for the RevenueCat dashboard's paywall
    /// metrics and experiment exposure. One model lives per presentation,
    /// so the impression is counted once however many times `load` runs.
    private let placement: String
    private var impressionTracked = false

    init(reason: PaywallReason) {
        placement = switch reason {
        case .loopFinished: "native-loop-finished"
        case .blocked: "native-blocked"
        case .chosen: "native-you-tab"
        }
    }

    // MARK: - Loading

    func load() async {
        #if DEBUG
        // `-uipaywallfake`: two made-up plans, no store at all, so the
        // layout can be screenshotted on any simulator.
        if ProcessInfo.processInfo.arguments.contains("-uipaywallfake") {
            plans = Self.plans(from: Self.fakePackages, eligibility: [:])
            selectedID = (plans.max { ($0.savingPercent ?? 0) < ($1.savingPercent ?? 0) } ?? plans[0]).id
            phase = .ready
            return
        }
        #endif
        guard Purchases.isConfigured else {
            phase = .unavailable
            return
        }
        phase = .loading
        notice = nil
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current else {
                throw PaywallError.noOffering
            }
            let eligibility = await Purchases.shared
                .checkTrialOrIntroDiscountEligibility(packages: offering.availablePackages)
            let built = Self.plans(from: offering.availablePackages, eligibility: eligibility)
            guard !built.isEmpty else { throw PaywallError.noOffering }
            plans = built
            remoteCopy = Self.copy(from: offering)
            // The best-value plan is the default: it's the one with the
            // trial and the saving, and the person can still tap another.
            selectedID = (built.max { ($0.savingPercent ?? 0) < ($1.savingPercent ?? 0) } ?? built[0]).id
            phase = .ready
            if !impressionTracked {
                impressionTracked = true
                // Resolves the offering from the cache `offerings()` just
                // filled, so it lands on the right experiment arm.
                Purchases.shared.trackCustomPaywallImpression(
                    CustomPaywallImpressionParams(paywallId: placement)
                )
            }
        } catch {
            plans = []
            phase = .unavailable
            notice = "Couldn't load the plans. Check your connection and try again."
        }
    }

    func select(_ plan: PaywallPlan) {
        guard phase == .ready else { return }
        selectedID = plan.id
    }

    // MARK: - Buying

    /// Runs the store's purchase sheet for the selected plan. Returns the
    /// customer info when a purchase went through, nil when it was
    /// cancelled or failed (with `notice` set for a real failure).
    func buy() async -> CustomerInfo? {
        guard phase == .ready, let plan = selected else { return nil }
        phase = .working
        notice = nil
        defer { phase = .ready }
        do {
            let result = try await Purchases.shared.purchase(package: plan.package)
            guard !result.userCancelled else { return nil }
            return result.customerInfo
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return nil
        } catch {
            notice = "That didn't go through. Nothing was charged. Please try again."
            return nil
        }
    }

    /// The store took the payment but the entitlement never turned up: a
    /// product that isn't attached to `Premium` in the dashboard, or a
    /// receipt still settling. Either way the screen has to say something,
    /// or someone who has just paid is left looking at the same paywall.
    func reportUnlockDidNotLand() {
        notice = "That went through, but Premium hasn't landed yet. Give it a moment, then tap Restore."
    }

    /// Restore for a new phone or a reinstall. Returns the customer info
    /// either way; the caller decides whether the entitlement is there.
    func restore() async -> CustomerInfo? {
        guard phase == .ready || phase == .unavailable else { return nil }
        let previous = phase
        phase = .working
        notice = nil
        defer { phase = previous }
        do {
            let info = try await Purchases.shared.restorePurchases()
            if info.entitlements[SubscriptionStore.entitlementID]?.isActive != true {
                notice = "No subscription found on this Apple Account."
            }
            return info
        } catch {
            notice = "Couldn't reach the App Store to restore. Please try again."
            return nil
        }
    }

    // MARK: - Shaping

    private enum PaywallError: Error { case noOffering }

    private static func plans(
        from packages: [Package],
        eligibility: [Package: IntroEligibility]
    ) -> [PaywallPlan] {
        guard !packages.isEmpty else { return [] }

        // The dearest way to hold the subscription for a year, per currency,
        // is what every other plan's saving is measured against.
        var dearestPerYear: [String: Decimal] = [:]
        for package in packages {
            let product = package.storeProduct
            guard let currency = product.currencyCode,
                  let perYear = product.pricePerYear?.decimalValue, perYear > 0 else { continue }
            dearestPerYear[currency] = max(dearestPerYear[currency] ?? 0, perYear)
        }

        let plans: [PaywallPlan] = packages.map { package in
            let product = package.storeProduct
            let term = term(of: product)

            var saving: Int?
            if let currency = product.currencyCode,
               let dearest = dearestPerYear[currency],
               let perYear = product.pricePerYear?.decimalValue, perYear > 0, perYear < dearest {
                let fraction = (dearest - perYear) / dearest
                let percent = Int((NSDecimalNumber(decimal: fraction).doubleValue * 100).rounded())
                if percent >= 5 { saving = percent }
            }

            // Named by period, never by the store's own product title:
            // "Yearly", "Monthly", "Weekly" says what the row is at a glance,
            // where "Satisfed Premium Annual" only repeats the app's name.
            return PaywallPlan(
                id: package.identifier,
                term: term,
                package: package,
                title: term.name,
                price: product.localizedPriceString,
                savingPercent: saving,
                trial: trial(for: package, eligibility: eligibility)
            )
        }
        return plans.sorted { $0.term.rank < $1.term.rank }
    }

    private static func term(of product: StoreProduct) -> PaywallPlan.Term {
        guard let period = product.subscriptionPeriod else { return .lifetime }
        switch (period.unit, period.value) {
        case (.year, _): return .year
        case (.month, 12): return .year
        case (.month, _): return .month
        case (.week, _): return .week
        case (.day, 7): return .week
        case (.day, _): return .day
        @unknown default: return .month
        }
    }

    /// The free trial on a package, only when the store says this person
    /// can still have it. A trial they've already used is not mentioned at
    /// all, so the button never promises something the sheet then denies.
    private static func trial(
        for package: Package,
        eligibility: [Package: IntroEligibility]
    ) -> PaywallPlan.Trial? {
        #if DEBUG
        // `-uipaywalltrial`: pretend the yearly plan carries a week's trial,
        // so the trial wording and timeline can be seen on the simulator's
        // test products, which have none.
        if package.storeProduct.subscriptionPeriod?.unit == .year,
           ProcessInfo.processInfo.arguments.contains("-uipaywalltrial") {
            return .init(value: 7, unit: .day)
        }
        #endif
        guard let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else { return nil }
        // Hidden only on a definite no. "Unknown" means the SDK couldn't
        // tell (no receipt yet, a fresh install); the store's own sheet
        // has the final word, and it shows the trial to anyone who
        // qualifies, so the screen offers it rather than hides it.
        switch eligibility[package]?.status {
        case .eligible, .unknown, .none: break
        case .ineligible, .noIntroOfferExists: return nil
        @unknown default: return nil
        }
        return .init(value: discount.subscriptionPeriod.value, unit: discount.subscriptionPeriod.unit)
    }

    #if DEBUG
    /// Weekly and annual at plausible prices, built from the SDK's own
    /// test products. Never talks to a store.
    private static var fakePackages: [Package] {
        func product(_ title: String, _ id: String, _ price: Decimal, _ shown: String, _ unit: SubscriptionPeriod.Unit) -> StoreProduct {
            TestStoreProduct(
                localizedTitle: title, price: price, localizedPriceString: shown,
                productIdentifier: id, productType: .autoRenewableSubscription,
                localizedDescription: "", subscriptionGroupIdentifier: "satisfed",
                subscriptionPeriod: .init(value: 1, unit: unit), locale: Locale(identifier: "en_US")
            ).toStoreProduct()
        }
        return [
            Package(identifier: "$rc_weekly", packageType: .weekly,
                    storeProduct: product("Weekly", "satisfed_1w_weekly", 2.99, "$2.99", .week),
                    offeringIdentifier: "fake", webCheckoutUrl: nil),
            Package(identifier: "$rc_annual", packageType: .annual,
                    storeProduct: product("Annual", "satisfed_1y_annual", 39.99, "$39.99", .year),
                    offeringIdentifier: "fake", webCheckoutUrl: nil),
        ]
    }
    #endif

    private static func copy(from offering: Offering) -> [String: String] {
        var out: [String: String] = [:]
        for key in ["headline", "subheadline", "cta"] {
            if let value = offering.metadata[key] as? String, !value.isEmpty {
                out[key] = value
            }
        }
        return out
    }
}
