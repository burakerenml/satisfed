//
//  PaywallHost.swift
//  Shiphaton App
//
//  The one place a paywall is ever presented from, applied to each screen
//  that can run into it.
//
//  The paywall is `PaywallScreen`, the app's own. What lives here is
//  everything around it: which screen shows it, closing it on every exit
//  the person has, and picking the blocked work back up once they've
//  paid, so a purchase lands them where they were instead of on an empty
//  screen.
//

import RevenueCat
import SwiftUI

private struct PaywallHostModifier: ViewModifier {
    /// Re-runs whatever the paywall interrupted. Called only after a
    /// purchase or restore that actually granted the entitlement.
    let onUnlocked: () -> Void

    @State private var hostID = UUID()
    @State private var center = PaywallCenter.shared
    @State private var store = SubscriptionStore.shared
    /// Set by a successful purchase, spent when the sheet closes, so the
    /// interrupted work resumes onto a screen that is visible again.
    @State private var resumeOnClose = false

    func body(content: Content) -> some View {
        content
            .onAppear { center.register(hostID) }
            .onDisappear { center.unregister(hostID) }
            .fullScreenCover(isPresented: isPresenting, onDismiss: resumeIfUnlocked) {
                PaywallScreen(
                    reason: center.reason ?? .chosen,
                    onUnlocked: { info in
                        await store.acknowledge(info)
                        guard store.isSubscribed else { return false }
                        resumeOnClose = true
                        return true
                    },
                    onClose: { center.dismiss() }
                )
            }
    }

    /// Presents only from the topmost registered host, so two nested sheets
    /// never both try.
    private var isPresenting: Binding<Bool> {
        Binding(
            get: { center.reason != nil && center.presentingHost == hostID },
            set: { shown in if !shown { center.dismiss() } }
        )
    }

    private func resumeIfUnlocked() {
        guard resumeOnClose else { return }
        resumeOnClose = false
        onUnlocked()
    }
}

extension View {
    /// Marks this screen as somewhere the paywall may be shown, and says
    /// what to re-run once it's paid for.
    ///
    /// Apply it to screens that make AI calls. `onUnlocked` should redo the
    /// call that was refused, so buying feels like the app catching up
    /// rather than the person starting over.
    func paywallHost(onUnlocked: @escaping () -> Void = {}) -> some View {
        modifier(PaywallHostModifier(onUnlocked: onUnlocked))
    }
}
