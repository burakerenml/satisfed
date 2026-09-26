//
//  Legal.swift
//  Shiphaton App
//
//  The two links App Review expects on every subscription screen.
//

import Foundation

enum Legal {
    /// Apple's standard licensed application agreement. Linking to it is
    /// what App Review asks for when an app has no terms of its own.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// The same privacy policy URL as the App Store listing. App Review
    /// opens it from the paywall.
    static let privacyPolicy = URL(string: "https://satisfed.app/privacy")!
}
