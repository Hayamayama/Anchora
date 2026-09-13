//
//  AnchoraTurn.swift
//  Anchora
//
//  The two pieces of state an AI question needs, as values rather than as a
//  drift of parallel properties on the view controller.
//
//  `AnchoraSelection` is what the reader has selected right now.  `AnchoraTurn`
//  is the snapshot taken when a request starts.  Keeping them apart is the
//  whole point: the reader keeps reading and selecting while an answer streams,
//  and Pin must attach that answer to the material it was actually asked about.
//

import Foundation
import PDFKit

// Whether a PDFSelection really contains characters is Skim's own careful
// workaround for PDFKit (a selection can report pages with no text ranges on
// them), so it is passed in rather than recomputed here.  That also keeps
// these values free of Skim, and repeatedly walking a selection's ranges out
// of the hot path.

/// Which navigator, if any, a turn's answer belongs in.
@objc public enum AnchoraMapKind: Int {
    case none = 0
    case paper = 1
    case study = 2
}

@objc(AnchoraSelection)
public final class AnchoraSelection: NSObject {

    /// Bumped whenever the reader's selection changes.  Text recognition runs
    /// off the main thread and compares this on completion, so a slow OCR pass
    /// cannot overwrite a selection the reader has since moved on from.
    @objc public let generation: Int
    @objc public let selection: PDFSelection?
    /// The text sent as context.  Nil while recognition is still running, or
    /// when it failed.
    @objc public let text: String?
    @objc public let imageDataURL: String?
    /// Set for a captured region; nil for a plain text selection.
    @objc public let page: PDFPage?
    @objc public let pageRect: NSRect
    @objc public let isRecognizingText: Bool
    /// What the CONTEXT card shows for this state.
    @objc public let contextDescription: String
    @objc public let hasTextSelection: Bool

    private init(generation: Int,
                 selection: PDFSelection?,
                 hasTextSelection: Bool,
                 text: String?,
                 imageDataURL: String?,
                 page: PDFPage?,
                 pageRect: NSRect,
                 isRecognizingText: Bool,
                 contextDescription: String) {
        self.generation = generation
        self.selection = selection
        self.hasTextSelection = hasTextSelection
        self.text = text
        self.imageDataURL = imageDataURL
        self.page = page
        self.pageRect = pageRect
        self.isRecognizingText = isRecognizingText
        self.contextDescription = contextDescription
        super.init()
    }

    // MARK: - State

    /// True when there is something to send, whether text, a recognised
    /// region, or an image.
    @objc public var hasContext: Bool {
        hasTextSelection || (text?.isEmpty == false) || (imageDataURL?.isEmpty == false)
    }

    // MARK: - Transitions

    private static func next(after previous: AnchoraSelection?) -> Int {
        (previous?.generation ?? 0) + 1
    }

    @objc public static func empty(message: String, after previous: AnchoraSelection?) -> AnchoraSelection {
        AnchoraSelection(generation: next(after: previous), selection: nil, hasTextSelection: false,
                         text: nil, imageDataURL: nil, page: nil, pageRect: .zero,
                         isRecognizingText: false, contextDescription: message)
    }

    /// A text selection whose own text layer is trustworthy.
    @objc public static func text(_ text: String,
                                  selection: PDFSelection,
                                  after previous: AnchoraSelection?) -> AnchoraSelection {
        AnchoraSelection(generation: next(after: previous),
                         selection: selection.copy() as? PDFSelection, hasTextSelection: true,
                         text: text, imageDataURL: nil, page: nil, pageRect: .zero,
                         isRecognizingText: false, contextDescription: text)
    }

    /// Recognition has started; `message` explains the wait.
    @objc public static func recognizing(selection: PDFSelection?,
                                         hasTextSelection: Bool,
                                         page: PDFPage?,
                                         pageRect: NSRect,
                                         message: String,
                                         after previous: AnchoraSelection?) -> AnchoraSelection {
        AnchoraSelection(generation: next(after: previous),
                         selection: selection?.copy() as? PDFSelection, hasTextSelection: hasTextSelection,
                         text: nil, imageDataURL: nil, page: page, pageRect: pageRect,
                         isRecognizingText: true, contextDescription: message)
    }

    /// A captured region sent as an image rather than as text.
    @objc public static func image(dataURL: String,
                                   page: PDFPage,
                                   pageRect: NSRect,
                                   text: String,
                                   message: String,
                                   after previous: AnchoraSelection?) -> AnchoraSelection {
        AnchoraSelection(generation: next(after: previous), selection: nil, hasTextSelection: false,
                         text: text, imageDataURL: dataURL, page: page, pageRect: pageRect,
                         isRecognizingText: false, contextDescription: message)
    }

    /// Recognition finished.  Keeps the same generation, so this result is
    /// still the answer to the selection the reader made.
    @objc public func byFinishingRecognition(text: String?, failureMessage: String) -> AnchoraSelection {
        let recognized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = (recognized?.isEmpty == false) ? recognized : nil
        return AnchoraSelection(generation: generation, selection: selection, hasTextSelection: hasTextSelection,
                                text: usable, imageDataURL: imageDataURL, page: page, pageRect: pageRect,
                                isRecognizingText: false,
                                contextDescription: usable ?? failureMessage)
    }
}

@objc(AnchoraTurn)
public final class AnchoraTurn: NSObject {

    /// The question as the reader sees it in the transcript, and as the title
    /// of a pinned note.
    @objc public let question: String
    /// The question plus its context, as kept in the local conversation memory.
    @objc public let conversationUserText: String
    @objc public let selection: PDFSelection?
    @objc public let page: PDFPage?
    @objc public let pageRect: NSRect
    @objc public let imageDataURL: String?
    @objc public let sourcePageIndexes: [NSNumber]
    /// A map answer is rendered into the navigator instead of the transcript:
    /// it is far too long to read as a chat bubble.
    @objc public let mapKind: AnchoraMapKind
    @objc public var isMap: Bool { mapKind != .none }

    /// The current phase, shown in the streaming bubble until output arrives.
    @objc public var status: String?
    @objc public var receivedOutput: Bool = false
    /// Accumulated as deltas arrive; this is what Pin and the conversation
    /// memory use.
    @objc public let response = NSMutableString()

    @objc public let hasTextSelection: Bool

    @objc public init(question: String,
                      conversationUserText: String,
                      selection: PDFSelection?,
                      hasTextSelection: Bool,
                      page: PDFPage?,
                      pageRect: NSRect,
                      imageDataURL: String?,
                      sourcePageIndexes: [NSNumber],
                      mapKind: AnchoraMapKind,
                      status: String?) {
        // A turn that was asked about a text selection is anchored to that
        // selection; one asked about a region or a whole page is anchored to
        // the page, never to both.
        self.hasTextSelection = hasTextSelection
        self.question = question
        self.conversationUserText = conversationUserText
        self.selection = hasTextSelection ? (selection?.copy() as? PDFSelection) : nil
        self.page = hasTextSelection ? nil : page
        self.pageRect = hasTextSelection ? .zero : pageRect
        self.imageDataURL = imageDataURL
        self.sourcePageIndexes = sourcePageIndexes
        self.mapKind = mapKind
        self.status = status
        super.init()
    }

    /// Pin needs an answer, and somewhere in the PDF to anchor it to.
    @objc public var canPin: Bool {
        receivedOutput && (hasTextSelection || page != nil)
    }
}
