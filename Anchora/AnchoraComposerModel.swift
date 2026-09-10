//
//  AnchoraComposerModel.swift
//  Anchora
//
//  The state of the ask bar: what is typed, which quick actions the current
//  reading profile offers, and whether a request is in flight.  The view
//  controller drives this and receives the reader's intent back through the
//  callbacks; it no longer builds or measures any of these controls.
//

import Foundation
import Combine

@objc(AnchoraComposerModel)
public final class AnchoraComposerModel: NSObject, ObservableObject {

    @Published public var question: String = ""
    @Published public private(set) var quickActionTitles: [String] = []
    @Published public private(set) var quickActionTooltips: [String] = []
    @Published public private(set) var placeholder: String = ""
    /// Send becomes Stop while a turn is live.
    @Published public private(set) var isRequestInFlight: Bool = false
    @Published public private(set) var canPin: Bool = false
    @Published public var webVerify: Bool = false

    /// Send, or Stop when a request is in flight.
    @objc public var onSubmit: (() -> Void)?
    @objc public var onQuickAction: ((Int) -> Void)?
    @objc public var onPin: (() -> Void)?
    @objc public var onClear: (() -> Void)?
    @objc public var onWebVerifyChanged: ((Bool) -> Void)?

    // MARK: - Driven by the view controller

    @objc public func questionText() -> String {
        question
    }

    @objc public func setQuestionText(_ text: String) {
        question = text
    }

    @objc public func setQuickActionTitles(_ titles: [String], tooltips: [String]) {
        quickActionTitles = titles
        quickActionTooltips = tooltips
    }

    @objc public func setPlaceholderText(_ text: String) {
        placeholder = text
    }

    @objc public func setRequestInFlight(_ inFlight: Bool) {
        isRequestInFlight = inFlight
    }

    @objc public func setPinEnabled(_ enabled: Bool) {
        canPin = enabled
    }
}
