//
//  AnchoraCredentials.swift
//  Anchora
//
//  Keychain access for the OpenAI API key, including migration of the key the
//  user entered before the PDFBuddy -> Anchora rename.
//

import Foundation

@objc(AnchoraCredentials)
public final class AnchoraCredentials: NSObject {

    private static let service = "Anchora.OpenAI"
    private static let legacyService = "PDFBuddy.OpenAI"
    private static let account = "APIKey"
    private static let label = "Anchora OpenAI API Key"
    private static let comment = "Used only for Anchora AI requests"

    /// The stored key, migrating the pre-rename item on first use.
    @objc public static func openAIAPIKey() -> String? {
        var status = SKPasswordStatus.notFound
        if let key = SKKeychain.password(forService: service, account: account, status: &status),
           key.isEmpty == false {
            return key
        }

        var legacyStatus = SKPasswordStatus.notFound
        if let legacyKey = SKKeychain.password(forService: legacyService, account: account, status: &legacyStatus),
           legacyKey.isEmpty == false {
            SKKeychain.setPassword(legacyKey, forService: service, account: account, label: label, comment: comment)
            return legacyKey
        }

        return nil
    }

    @objc public static func hasOpenAIAPIKey() -> Bool {
        (openAIAPIKey()?.isEmpty == false)
    }

    @objc public static func storeOpenAIAPIKey(_ key: String) {
        guard key.isEmpty == false else { return }
        var status = SKPasswordStatus.notFound
        _ = SKKeychain.password(forService: service, account: account, status: &status)
        if status == .found {
            _ = SKKeychain.updatePassword(key,
                                          service: service,
                                          account: account,
                                          label: label,
                                          comment: comment,
                                          forService: service,
                                          account: account)
        } else {
            SKKeychain.setPassword(key, forService: service, account: account, label: label, comment: comment)
        }
    }
}
