//
//  DeviceIdentity.swift
//  Shiphaton App
//
//  One id for this person, stable enough to hang a free trial on.
//
//  It lives in the Keychain, which outlives deleting the app: reinstalling
//  lands on the same id, so the one free loop is one free loop rather than
//  one per install. UserDefaults would have been wiped by the delete, and
//  identifierForVendor resets once every app from this vendor is gone.
//
//  The same id is what RevenueCat is configured with, so the subscription,
//  the server's ledger row and the person are all the same key. That also
//  means a purchase restores cleanly onto a reinstall with no sign-in.
//

import Foundation
import UIKit

enum DeviceIdentity {

    /// The id sent with every AI call and handed to RevenueCat at launch.
    /// Resolved once per launch; the Keychain read only happens on the
    /// first touch.
    static let current: String = resolve()

    private static let service = "app.satisfed.identity"
    private static let account = "appUserID"

    // MARK: - Resolving

    private static func resolve() -> String {
        if let stored = read() { return stored }
        let minted = "sat-" + UUID().uuidString
        if write(minted) { return minted }
        // Lost a race with another write, or the item was already there.
        if let stored = read() { return stored }

        // The Keychain refused us. Rather than mint a throwaway id on every
        // launch (which would hand out a fresh free loop each time), fall
        // back to the vendor id, which at least holds still while the app
        // is installed.
        if let vendor = UIDevice.current.identifierForVendor?.uuidString {
            return "sat-" + vendor
        }
        return minted
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    private static func write(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        var query = baseQuery
        query[kSecValueData as String] = data
        // After first unlock, not "this device only": a restored backup
        // should carry the id across to the new phone along with everything
        // else the person owns.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem {
            // Someone wrote between our read and our add. Their value wins.
            return false
        }
        return false
    }
}
