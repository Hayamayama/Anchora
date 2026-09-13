//
//  AnchoraMapSection.swift
//  Anchora
//
//  One navigable section of a map over a PDF.  Both kinds of map -- the
//  evidence-first paper map and the reading-order study map -- are lists of
//  these, which is why the navigator can render either.
//

import Foundation

@objc(AnchoraMapSection)
public final class AnchoraMapSection: NSObject {
    @objc public let title: String
    @objc public let text: String
    /// Zero-based page indexes cited anywhere in this section, in first-seen order.
    @objc public let pageIndexes: [NSNumber]

    init(title: String, text: String, pageIndexes: [NSNumber]) {
        self.title = title
        self.text = text
        self.pageIndexes = pageIndexes
    }
}
