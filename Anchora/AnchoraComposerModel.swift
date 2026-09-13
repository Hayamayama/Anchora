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
    /// Bumped to ask the ask bar to take keyboard focus.  A counter rather
    /// than a flag, so two requests in a row both land even if the field was
    /// already focused once.
    @Published public private(set) var focusRequest: Int = 0

    /// The height the ask bar and its rows need for what is currently typed.
    ///
    /// The composer is still given an explicit height by its AppKit host --
    /// nothing here is allowed to report an intrinsic size, which is what made
    /// the old hand-built row measure itself into the ground.  What changed is
    /// that the number is no longer a constant: SwiftUI lays the text out at
    /// the width the sidebar gave it and hands the resulting height back, and
    /// the host sets that as the constraint.  That direction is safe.  Width is
    /// set by the sidebar and never by this view, so height cannot feed back
    /// into the width that produced it.
    @objc public private(set) var contentHeight: CGFloat = AnchoraComposerModel.minimumHeight
    @objc public var onHeightChange: ((CGFloat) -> Void)?

    /// One line of question, plus the quick action row and the secondary row.
    @objc public static let minimumHeight: CGFloat = 84.0
    /// About six lines.  Past that the field scrolls: a composer that can eat
    /// the whole sidebar is worse than one that scrolls.
    @objc public static let maximumHeight: CGFloat = 184.0

    @objc public static func clampHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return minimumHeight }
        return min(max(height, minimumHeight), maximumHeight)
    }

    /// One line of text, which is what the field starts at.
    @objc public static let minimumFieldHeight: CGFloat = 21.0
    /// About six lines; past that the field scrolls.
    @objc public static let maximumFieldHeight: CGFloat = 108.0

    /// How tall the text itself needs to be, as opposed to the whole composer.
    @Published public private(set) var fieldHeight: CGFloat = AnchoraComposerModel.minimumFieldHeight

    @objc public static func clampFieldHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return minimumFieldHeight }
        return min(max(height, minimumFieldHeight), maximumFieldHeight)
    }

    func reportFieldHeight(_ height: CGFloat) {
        let clamped = AnchoraComposerModel.clampFieldHeight(height)
        guard abs(clamped - fieldHeight) >= 0.5 else { return }
        fieldHeight = clamped
    }

    /// Called by the view whenever its laid-out height changes.  Sub-point
    /// changes are dropped: a constraint updated on every keystroke by a
    /// fraction of a point is just layout churn.
    func reportContentHeight(_ height: CGFloat) {
        let clamped = AnchoraComposerModel.clampHeight(height)
        guard abs(clamped - contentHeight) >= 0.5 else { return }
        contentHeight = clamped
        onHeightChange?(clamped)
    }

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
        // Sending clears the field, and the composer has to come back down
        // with it.  Typing reports its own height, but an emptied field has no
        // keystroke to report on.
        if text.isEmpty {
            fieldHeight = AnchoraComposerModel.minimumFieldHeight
        }
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

    /// Puts the caret in the ask bar — used when the reader chooses Ask AI from
    /// the selection popover and expects to start typing.
    @objc public func focusQuestionField() {
        focusRequest &+= 1
    }
}
