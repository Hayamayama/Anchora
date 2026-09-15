//
//  AnchoraHosting.swift
//  Anchora
//
//  Bridges the SwiftUI sidebar views into the AppKit view hierarchy.
//  NSHostingView is generic, so Objective-C needs these factories.
//

import AppKit
import SwiftUI

@objc(AnchoraHosting)
public final class AnchoraHosting: NSObject {

    /// `sizingOptions` is deliberately empty.  A hosting view that reports an
    /// intrinsic content size would re-introduce exactly the measurement loop
    /// the hand-rolled chat stack used to hit while a PDF was opening: the
    /// sidebar sizes the view, the view measures its text, and the resulting
    /// height feeds back into the sidebar.  These views are sized purely by
    /// the constraints their host gives them.
    private static func hostingView<Content: View>(_ content: Content) -> NSView {
        let view = NSHostingView(rootView: content)
        view.sizingOptions = []
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    @objc public static func headerView(model: AnchoraHeaderModel) -> NSView {
        hostingView(AnchoraHeaderView(model: model))
    }

    /// The fixed height the header's host should give it.
    @objc public static var headerHeight: CGFloat { AnchoraHeaderView.height }

    @objc public static func composerView(model: AnchoraComposerModel) -> NSView {
        hostingView(AnchoraComposerView(model: model))
    }

    /// The fixed height the composer's host should give it.
    @objc public static var composerHeight: CGFloat { AnchoraComposerView.height }

    @objc public static func chatView(model: AnchoraChatModel) -> NSView {
        hostingView(AnchoraChatView(model: model))
    }

    /// The tab strip and whichever of the four faces is selected: the
    /// transcript, the map, the inbox, or the review queue.  One hosting
    /// view, so the sidebar never has to compute how tall a map ought to be.
    ///
    /// `pageLabels` is captured when the view is built; the host rebuilds the
    /// root view through `updatePaneView(...)` when a new document is opened.
    @objc public static func paneView(pane: AnchoraPaneModel,
                                      chat: AnchoraChatModel,
                                      map: AnchoraMapModel,
                                      inbox: AnchoraInboxModel,
                                      review: AnchoraReviewModel,
                                      pageLabels: [String]) -> NSView {
        hostingView(AnchoraPaneView(pane: pane, chat: chat, map: map, inbox: inbox, review: review, pageLabels: pageLabels))
    }

    @objc public static func updatePaneView(_ view: NSView,
                                            pane: AnchoraPaneModel,
                                            chat: AnchoraChatModel,
                                            map: AnchoraMapModel,
                                            inbox: AnchoraInboxModel,
                                            review: AnchoraReviewModel,
                                            pageLabels: [String]) {
        guard let hosting = view as? NSHostingView<AnchoraPaneView> else { return }
        hosting.rootView = AnchoraPaneView(pane: pane, chat: chat, map: map, inbox: inbox, review: review, pageLabels: pageLabels)
    }
}
