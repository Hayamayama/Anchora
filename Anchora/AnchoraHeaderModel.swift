//
//  AnchoraHeaderModel.swift
//  Anchora
//
//  The sidebar's identity row and the CONTEXT card: what Anchora is currently
//  reading for, and what it would send if you asked right now.
//

import Foundation
import Combine

@objc(AnchoraHeaderModel)
public final class AnchoraHeaderModel: NSObject, ObservableObject {

    @Published public private(set) var title: String = ""
    @Published public private(set) var subtitle: String = ""
    @Published public private(set) var contextTitle: String = ""
    @Published public private(set) var contextText: String = ""
    @Published public private(set) var isScientific: Bool = false

    @objc public var onProfileChange: ((Bool) -> Void)?
    /// The ••• menu is still an NSMenu: it is built from the document's own
    /// notes and their colours, which is Skim's world rather than Anchora's.
    @objc public var onMoreActions: (() -> Void)?

    @objc public func setProfile(scientific: Bool, title: String, subtitle: String, contextTitle: String) {
        isScientific = scientific
        self.title = title
        self.subtitle = subtitle
        self.contextTitle = contextTitle
    }

    @objc public func setContextText(_ text: String) {
        contextText = text
    }

    func selectProfile(scientific: Bool) {
        guard scientific != isScientific else { return }
        isScientific = scientific
        onProfileChange?(scientific)
    }
}
