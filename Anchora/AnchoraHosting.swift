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

    /// `pageLabels` is captured when the view is built; the host rebuilds the
    /// root view through `updatePaperMapView(_:model:pageLabels:)` when a new
    /// document is opened.
    @objc public static func paperMapView(model: AnchoraPaperMapModel, pageLabels: [String]) -> NSView {
        hostingView(AnchoraPaperMapView(model: model, pageLabels: pageLabels))
    }

    @objc public static func updatePaperMapView(_ view: NSView, model: AnchoraPaperMapModel, pageLabels: [String]) {
        guard let hosting = view as? NSHostingView<AnchoraPaperMapView> else { return }
        hosting.rootView = AnchoraPaperMapView(model: model, pageLabels: pageLabels)
    }
}
