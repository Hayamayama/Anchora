//
//  AnchoraSettings.swift
//  Anchora
//
//  Persisted user choices for the AI sidebar: reading profile, response
//  language, and model.  Pure Foundation, no AppKit and no Skim types.
//

import Foundation

@objc public enum AnchoraReadingProfile: Int {
    case study = 0
    case scientific = 1
}

@objc public enum AnchoraResponseLanguage: Int {
    case traditionalChinese = 0
    case english = 1
}

/// One entry in the curated model list shown in the ••• menu.
@objc(AnchoraModelChoice)
public final class AnchoraModelChoice: NSObject {
    @objc public let identifier: String
    @objc public let title: String

    init(identifier: String, title: String) {
        self.identifier = identifier
        self.title = title
    }
}

@objc(AnchoraSettings)
public final class AnchoraSettings: NSObject {

    @objc(sharedSettings) public static let shared = AnchoraSettings()

    private enum Key {
        static let readingProfile = "Anchora.AIReadingProfile"
        static let responseLanguage = "Anchora.AIResponseLanguage"
        static let model = "Anchora.AIModel"
    }

    /// The safe fallback when nothing is stored, or when a stored model is no
    /// longer part of the curated list.
    @objc public static let defaultModelIdentifier = "gpt-5-mini"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    // MARK: - Reading profile

    @objc public var readingProfile: AnchoraReadingProfile {
        get { AnchoraReadingProfile(rawValue: defaults.integer(forKey: Key.readingProfile)) ?? .study }
        set { defaults.set(newValue.rawValue, forKey: Key.readingProfile) }
    }

    @objc public var isScientific: Bool {
        readingProfile == .scientific
    }

    // MARK: - Response language

    @objc public var responseLanguage: AnchoraResponseLanguage {
        get { AnchoraResponseLanguage(rawValue: defaults.integer(forKey: Key.responseLanguage)) ?? .traditionalChinese }
        set { defaults.set(newValue.rawValue, forKey: Key.responseLanguage) }
    }

    @objc public var usesTraditionalChinese: Bool {
        responseLanguage == .traditionalChinese
    }

    // MARK: - Model

    /// Deliberately small.  These are curated Responses/vision choices rather
    /// than every model an API key might list; availability is still decided
    /// by the user's own API project.
    @objc public static let availableModels: [AnchoraModelChoice] = [
        AnchoraModelChoice(identifier: "gpt-5.6-luna", title: "GPT-5.6 Luna — Everyday study"),
        AnchoraModelChoice(identifier: "gpt-5.6-terra", title: "GPT-5.6 Terra — Recommended"),
        AnchoraModelChoice(identifier: "gpt-5.6-sol", title: "GPT-5.6 Sol — Deep paper analysis"),
        AnchoraModelChoice(identifier: AnchoraSettings.defaultModelIdentifier, title: "GPT-5 mini — Legacy economy"),
    ]

    @objc public var modelIdentifier: String {
        get {
            let saved = defaults.string(forKey: Key.model)
            let known = AnchoraSettings.availableModels.contains { $0.identifier == saved }
            return known ? saved! : AnchoraSettings.defaultModelIdentifier
        }
        set {
            guard AnchoraSettings.availableModels.contains(where: { $0.identifier == newValue }) else { return }
            defaults.set(newValue, forKey: Key.model)
        }
    }
}
