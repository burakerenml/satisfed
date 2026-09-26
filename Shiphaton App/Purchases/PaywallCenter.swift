//
//  PaywallCenter.swift
//  Shiphaton App
//
//  Decides when the paywall is asked for, and which screen puts it on
//  screen.
//
//  The "which screen" half is the fiddly part. Every AI surface in the app
//  is itself inside a sheet, and asking a view that is covered (or halfway
//  through being dismissed) to present another sheet is how you end up
//  looking at nothing. So hosts register while they're on screen, the
//  newest one wins, and exactly one of them is ever presenting.
//

import Foundation
import SwiftUI

/// Why the paywall came up. It only picks the copy around the RevenueCat
/// paywall; the paywall itself is configured in the dashboard.
enum PaywallReason: Equatable {
    /// The server refused an AI call: the free loop is spent.
    case blocked
    /// The free loop just finished on its summary. The good moment.
    case loopFinished
    /// They asked for it, from the You tab.
    case chosen
}

@MainActor
@Observable
final class PaywallCenter {

    static let shared = PaywallCenter()

    /// Non-nil while the paywall should be up.
    private(set) var reason: PaywallReason?

    /// Hosts currently on screen, oldest first. The last one is the one
    /// closest to the person's eyes, so it's the one that presents.
    private var hosts: [UUID] = []

    private init() {}

    var presentingHost: UUID? { hosts.last }

    // MARK: - Asking

    /// Puts the paywall up, unless it already is. Silently does nothing
    /// when no host is on screen, which is the right answer: there is
    /// nowhere safe to present from, and the surfaces that can be blocked
    /// all host one.
    func request(_ reason: PaywallReason) {
        guard self.reason == nil else { return }
        guard !hosts.isEmpty else { return }
        self.reason = reason
    }

    /// The soft offer, made once a free loop reaches its summary. Only
    /// lands when the loop really is spent and nothing has been bought, so
    /// it's safe to call whenever a summary appears.
    func offerAfterFreeLoop() {
        let store = SubscriptionStore.shared
        guard store.hasAnswer, !store.isSubscribed, store.freeLoopSpent else { return }
        request(.loopFinished)
    }

    func dismiss() {
        reason = nil
    }

    // MARK: - Hosts

    func register(_ id: UUID) {
        guard !hosts.contains(id) else { return }
        hosts.append(id)
    }

    func unregister(_ id: UUID) {
        hosts.removeAll { $0 == id }
        // The screen that was showing it has gone. Take the paywall with
        // it rather than leave it pointing at nothing.
        if hosts.isEmpty { reason = nil }
    }
}
