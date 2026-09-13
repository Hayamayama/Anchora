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
    /// The single line the header shows.  The card this replaced was 86 points
    /// of sidebar spent mostly on text the reader could already see selected
    /// in the PDF beside it; the states worth the space are the ones the PDF
    /// cannot show -- OCR still running, a region captured as an image, the
    /// whole document attached -- and those are one line each anyway.
    @Published public private(set) var contextSummary: String = ""
    /// True only when the context is text Anchora extracted, which is the one
    /// case where there is more to see than the summary: OCR output should be
    /// checkable before it is paid for.
    @Published public private(set) var isContextExpandable: Bool = false
    @Published public private(set) var isScientific: Bool = false

    /// Where the ••• button ended up, in the header view's own coordinates.
    /// The menu is an NSMenu popped by the view controller, and guessing at
    /// the corner got it wrong: NSHostingView is flipped, so a y measured up
    /// from the bottom landed the menu under the card instead of under the
    /// button.  SwiftUI reports the real frame instead.
    @objc public private(set) var moreActionsAnchor: CGRect = .zero

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

    @objc public func setContextText(_ text: String, expandable: Bool) {
        contextText = text
        contextSummary = AnchoraHeaderModel.summary(of: text)
        isContextExpandable = expandable && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// One line, whatever arrives.  PDF text layers are full of hard line
    /// breaks that mean nothing outside the page's own column width, so they
    /// are collapsed rather than allowed to truncate the summary at the first
    /// one.
    static func summary(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    func setMoreActionsAnchor(_ frame: CGRect) {
        moreActionsAnchor = frame
    }

    /// Where to pop the ••• menu, in the host view's coordinates.
    ///
    /// SwiftUI reports frames from the top left, which matches a flipped host
    /// and is upside down in an unflipped one.  Getting that backwards put the
    /// menu below the CONTEXT card instead of below the button, so the
    /// conversion lives here where it can be tested rather than being guessed
    /// at the call site.
    @objc public func moreActionsMenuLocation(inViewBounds bounds: CGRect, isFlipped: Bool) -> CGPoint {
        let gap: CGFloat = 4.0
        guard moreActionsAnchor.isEmpty == false else {
            // Nothing reported yet: the view's top-right corner.
            return CGPoint(x: bounds.width - 36.0, y: isFlipped ? 0.0 : bounds.height)
        }
        let belowInTopLeftSpace = moreActionsAnchor.maxY + gap
        return CGPoint(x: moreActionsAnchor.minX,
                       y: isFlipped ? belowInTopLeftSpace : bounds.height - belowInTopLeftSpace)
    }

    func selectProfile(scientific: Bool) {
        guard scientific != isScientific else { return }
        isScientific = scientific
        onProfileChange?(scientific)
    }
}
