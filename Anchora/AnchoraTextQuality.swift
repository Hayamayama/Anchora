//
//  AnchoraTextQuality.swift
//  Anchora
//
//  Deciding whether a PDF's text layer can be trusted for a given selection.
//  Pure arithmetic: the caller supplies the strings, including Skim's own
//  alien-stripped variant, so this stays testable without PDFKit.
//

import Foundation

@objc(AnchoraTextQuality)
public final class AnchoraTextQuality: NSObject {

    /// A slide deck's text layer is often a broken font mapping rather than
    /// text: the characters live in a private use plane and come back as
    /// gibberish. Stripping them leaves either nothing, or so little of the
    /// original that the layer cannot be trusted -- in both cases Vision on a
    /// rendering of the page is the better source.
    @objc public static func needsRecognition(rawText: String,
                                        cleanedText: String,
                                        textWithoutAliens: String) -> Bool {
        if rawText.isEmpty { return true }
        let removed = rawText.count - textWithoutAliens.count
        guard removed > 0 else { return false }
        // Either a third or more of the selection was unreadable, or cleaning
        // it left nothing usable at all.
        return removed * 3 >= rawText.count || cleanedText.isEmpty
    }
}
