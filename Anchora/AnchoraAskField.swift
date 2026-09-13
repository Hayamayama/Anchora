//
//  AnchoraAskField.swift
//  Anchora
//
//  The ask bar's text view.
//
//  SwiftUI's own multi-line TextField submits on Return whether or not Shift
//  is held, which leaves no way to type a second line -- and a second line is
//  exactly what answering a quiz or writing out a recalled paragraph needs.
//  So the key goes through an NSTextView this file owns, where Return and
//  Shift-Return are told apart explicitly rather than inferred from whatever
//  the framework does with a field editor.
//
//  It reports its laid-out height instead of claiming an intrinsic size.  The
//  distinction matters here more than it looks: an intrinsic size is a
//  negotiation, and the sidebar has been brought down by one of those before.
//  This is one-way -- the width arrives from the sidebar, the height leaves --
//  so there is no cycle for the layout to fall into.
//

import AppKit
import SwiftUI

struct AnchoraAskField: NSViewRepresentable {

    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 13.0)
    /// Bumped by the model when the ask bar should take the keyboard.
    var focusRequest: Int
    var onSubmit: () -> Void
    /// The height the text needs at its current width, already laid out.
    var onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AnchoraAskTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = { onSubmit() }
        textView.font = font
        textView.isRichText = false
        textView.isEditable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        // Without all of these the container keeps an unbounded width, every
        // line lays out as one long line, and the measured height never moves
        // off a single line however much is typed.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 2.0, height: 4.0)
        textView.textContainer?.containerSize = NSSize(width: 0.0,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 3.0
        // Substitutions belong in prose, not in a field where a quoted term or
        // a minus sign has to survive being sent to a model verbatim.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // Past the cap the field scrolls rather than growing further, which is
        // the only reason this is in a scroll view at all.
        scrollView.verticalScrollElasticity = .none
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AnchoraAskTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = { onSubmit() }
        if textView.string != text {
            textView.string = text
        }
        if context.coordinator.servedFocusRequest != focusRequest {
            context.coordinator.servedFocusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
            }
        }
        context.coordinator.reportHeight(of: textView, deferred: true)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: AnchoraAskField
        weak var textView: AnchoraAskTextView?
        var servedFocusRequest: Int
        private var lastReportedHeight: CGFloat = 0.0

        init(_ parent: AnchoraAskField) {
            self.parent = parent
            self.servedFocusRequest = parent.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? AnchoraAskTextView else { return }
            parent.text = textView.string
            // Typing is a user event rather than a view-update pass, so the
            // new height can be applied straight away.  Deferring it here made
            // the field lag a line behind what was in it.
            reportHeight(of: textView, deferred: false)
        }

        /// Laid out rather than estimated: a wrapped line and a typed line are
        /// the same to the reader and must be the same to the layout.
        func reportHeight(of textView: AnchoraAskTextView, deferred: Bool) {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer
            else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let height = max(used + textView.textContainerInset.height * 2.0, 1.0)
            guard abs(height - lastReportedHeight) >= 0.5 else { return }
            let report = parent.onHeightChange
            guard deferred else {
                lastReportedHeight = height
                report(height)
                return
            }
            // updateNSView runs inside SwiftUI's own layout pass, and changing
            // observed state from in there is what "Modifying state during view
            // update" warns about.  The record of what was reported is only
            // updated once it actually has been, so a dropped hand-off is
            // retried on the next pass rather than silently swallowed.
            DispatchQueue.main.async { [weak self] in
                self?.lastReportedHeight = height
                report(height)
            }
        }
    }
}

/// Return sends, Shift-Return starts a line.  Everything else is an ordinary
/// text view.
final class AnchoraAskTextView: NSTextView {

    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn {
            if event.modifierFlags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }
}
