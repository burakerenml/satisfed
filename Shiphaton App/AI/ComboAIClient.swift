//
//  ComboAIClient.swift
//  Shiphaton App
//
//  The app's only door to the combo AI: a single Firebase callable
//  function (`comboAI`). The Azure key lives server-side only, in Secret
//  Manager, never in this binary. Firebase App Check attaches an
//  attestation token to every call automatically (App Attest on device, a
//  debug provider in DEBUG builds) — the function rejects anything that
//  doesn't carry a valid one. No sign-in involved on either side.
//

import FirebaseFunctions
import UIKit

enum AIError: LocalizedError {
    case invalidImage
    case invalidResponse
    /// The free loop is spent and there's no subscription. The paywall has
    /// already been asked for by the time this is thrown; callers only need
    /// to stop what they were doing.
    case paywallRequired
    case request(Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Couldn't read that photo."
        case .invalidResponse: "The AI sent back something we couldn't read."
        case .paywallRequired: "This one needs a subscription."
        case .request(let error): error.localizedDescription
        }
    }

    // MARK: - What to tell the person

    /// True when the failure was the network, not the AI: no connection,
    /// the connection dropping mid-call, or nothing answering at all.
    static func isOffline(_ error: Error) -> Bool {
        if let ai = error as? AIError, case .request(let inner) = ai { return isOffline(inner) }
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                     NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                     NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff,
                     NSURLErrorDataNotAllowed:
                    return true
                default:
                    break
                }
            }
            if nsError.domain == FunctionsErrorDomain,
               nsError.code == FunctionsErrorCode.unavailable.rawValue,
               nsError.userInfo[NSUnderlyingErrorKey] == nil {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// The call gave up waiting.
    static func isTimeout(_ error: Error) -> Bool {
        if let ai = error as? AIError, case .request(let inner) = ai { return isTimeout(inner) }
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut { return true }
            if nsError.domain == FunctionsErrorDomain,
               nsError.code == FunctionsErrorCode.deadlineExceeded.rawValue {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// One plain sentence for the screen, never a raw error. `what` names
    /// the thing that didn't happen, in the person's terms ("read the
    /// photo", "deal the cards").
    @MainActor
    static func friendlyMessage(for error: Error, what: String) -> String {
        if isOffline(error) || !NetworkMonitor.shared.isOnline {
            return "You're offline right now. Connect to the internet and we'll \(what)."
        }
        if isTimeout(error) {
            return "That took longer than it should. Give it another go."
        }
        if let ai = error as? AIError {
            switch ai {
            case .invalidImage:
                return "That photo didn't come through. Try another one."
            case .invalidResponse:
                return "We couldn't make sense of the answer that came back. Try once more."
            case .paywallRequired:
                return "This one needs Premium."
            case .request:
                break
            }
        }
        return "Something went wrong on our side, not yours. Try again in a moment."
    }

    /// The offline line to show before a call is even attempted.
    static let offlineMessage = "You're offline right now. Connect to the internet and try again."
}

enum ComboAIClient {
    private static let functions = Functions.functions()

    // MARK: - Bot 1: snack analyzer (vision)

    static func analyzeSnack(image: UIImage, note: String, profile: String) async throws -> SnackAnalysis {
        guard let data = image.jpegData(compressionQuality: 0.7) else { throw AIError.invalidImage }
        let result = try await call([
            "bot": "snackAnalyzer",
            "imageBase64": data.base64EncodedString(),
            "mimeType": "image/jpeg",
            "note": note,
            "profile": profile,
        ])
        return try decode(result, as: SnackAnalysis.self)
    }

    // MARK: - Bot 3: swipe combo builder (deck + summary)

    static func swipeDeck(craving: String, accepted: [String], rejected: [String], note: String, profile: String) async throws -> SwipeDeckResult {
        let result = try await call([
            "bot": "swipeBuilder",
            "mode": "DECK",
            "payload": ["craving": craving, "accepted": accepted, "rejected": rejected, "user_note": note],
            "profile": profile,
        ])
        return try decode(result, as: SwipeDeckResult.self)
    }

    static func swipeSummary(craving: String, accepted: [String], compoundsCovered: [String], note: String, profile: String) async throws -> SwipeSummaryResult {
        let result = try await call([
            "bot": "swipeBuilder",
            "mode": "SUMMARY",
            "payload": ["craving": craving, "accepted": accepted, "compounds_covered": compoundsCovered, "user_note": note],
            "profile": profile,
        ])
        return try decode(result, as: SwipeSummaryResult.self)
    }

    // MARK: - Bot 2: idea generator (recipe maker)

    static func generateIdeas(message: String, profile: String) async throws -> GeneratedIdeas {
        let result = try await call([
            "bot": "ideaGenerator",
            "message": message,
            "profile": profile,
        ])
        return try decode(result, as: GeneratedIdeas.self)
    }

    // MARK: - Bot 4: craving translator

    /// `note` is free context (mood, what was eaten, time of day); `userData`
    /// is the person's own recent history as built by `RecentData`, which
    /// the prompt mines for patterns. Both are optional.
    static func translateCraving(craving: String, note: String, userData: [String: Any]?, profile: String) async throws -> CravingTranslation {
        var data: [String: Any] = [
            "bot": "cravingTranslator",
            "craving": craving,
            "note": note,
            "profile": profile,
        ]
        if let userData { data["userData"] = userData }
        let result = try await call(data)
        return try decode(result, as: CravingTranslation.self)
    }

    // MARK: - Wire format

    private static func call(_ data: [String: Any]) async throws -> Any {
        var body = data
        // The gate on the other side is keyed on this. It decides whether
        // the call is answered at all; nothing here can talk it round.
        body["appUserID"] = DeviceIdentity.current
        // Right after a purchase or restore the server's mirror of
        // RevenueCat can still say "free". This tells the gate to ask
        // RevenueCat directly, so the person who just paid isn't refused.
        if await SubscriptionStore.shared.wantsFreshGate {
            body["fresh"] = true
        }
        do {
            let result = try await functions.httpsCallable("comboAI").call(body)
            return result.data
        } catch {
            if isPaywall(error) {
                // Every call site swallows AI failures and falls back to the
                // offline library, which is the right behaviour for a flaky
                // network and the wrong one here: nobody would ever see the
                // paywall. So the paywall is asked for from the one place
                // every call passes through.
                Task { @MainActor in PaywallCenter.shared.request(.blocked) }
                throw AIError.paywallRequired
            }
            throw AIError.request(error)
        }
    }

    /// The gate's refusal, as it arrives through a Firebase callable: a
    /// permission-denied carrying our own code in its details.
    private static func isPaywall(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else { return false }
        if let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
           details["code"] as? String == "PAYWALL_REQUIRED" {
            return true
        }
        // Details can be stripped in transit; the code plus the message the
        // function throws is enough on its own.
        return nsError.code == FunctionsErrorCode.permissionDenied.rawValue
            && nsError.localizedDescription.contains("PAYWALL_REQUIRED")
    }

    private static func decode<T: Decodable>(_ raw: Any, as type: T.Type) throws -> T {
        guard JSONSerialization.isValidJSONObject(raw) else { throw AIError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
