//
//  AnchoraComposerView.swift
//  Anchora
//
//  The quick actions and the ask bar.
//
//  This row is where the sidebar's worst bug lived: building it from
//  NSStackView arranged subviews made AppKit ask for a fitting size while the
//  sidebar was still being installed, and the resulting measurement loop could
//  consume tens of gigabytes as a PDF opened.  Equal-width buttons are a layout
//  the framework can express directly.
//

import SwiftUI

/// Carries the composer's laid-out height out to its AppKit host.
private struct AnchoraComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0.0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0.0 {
            value = next
        }
    }
}

struct AnchoraComposerView: View {

    @ObservedObject var model: AnchoraComposerModel

    /// The height the host starts with, before anything is typed.
    static let height: CGFloat = AnchoraComposerModel.minimumHeight

    var body: some View {
        VStack(spacing: 6.0) {
            quickActions
            askBar
            secondaryActions
        }
        .fixedSize(horizontal: false, vertical: true)
        // The host still sets this view's height with a constraint; it just
        // gets the number from here now.  Measuring the laid-out content and
        // reporting it is not the same as reporting an intrinsic size: the
        // width comes from the sidebar and is never influenced by what is
        // measured, so there is no cycle to fall into.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: AnchoraComposerHeightKey.self, value: proxy.size.height)
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(AnchoraComposerHeightKey.self) { height in
            model.reportContentHeight(height)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 4.0) {
            ForEach(Array(model.quickActionTitles.enumerated()), id: \.offset) { index, title in
                Button {
                    model.onQuickAction?(index)
                } label: {
                    // The width has to go on the label: widening the button's
                    // frame alone leaves its bezel at the title's natural size,
                    // centred in the space.
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .help(index < model.quickActionTooltips.count ? model.quickActionTooltips[index] : title)
            }
        }
        .controlSize(.small)
        .frame(height: 22.0)
    }

    /// Return sends; Shift-Return starts a new line.  A question worth typing
    /// over several lines -- a list of answers to a quiz, a paragraph recalled
    /// from memory -- should grow downwards rather than scroll away to the
    /// right.
    private var askBar: some View {
        HStack(alignment: .bottom, spacing: 8.0) {
            ZStack(alignment: .topLeading) {
                // NSTextView has no placeholder, and the private attribute for
                // one is not worth depending on.
                if model.question.isEmpty {
                    Text(model.placeholder)
                        .font(.system(size: 13.0))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6.0)
                        .padding(.vertical, 4.0)
                        .allowsHitTesting(false)
                }
                AnchoraAskField(text: $model.question,
                                focusRequest: model.focusRequest,
                                onSubmit: { model.onSubmit?() },
                                onHeightChange: { model.reportFieldHeight($0) })
                    .frame(height: model.fieldHeight)
            }
            .background(RoundedRectangle(cornerRadius: 6.0, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6.0, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor)))

            Button(model.isRequestInFlight ? "Stop" : "Send") {
                model.onSubmit?()
            }
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 6.0) {
            Button("Pin latest answer") { model.onPin?() }
                .disabled(model.canPin == false)
                .help("Add the latest answer to the PDF as an editable note")
            Button("Clear chat") { model.onClear?() }
                .help("Clear this conversation and its local memory")
            Spacer(minLength: 4.0)
            Toggle("Web verify", isOn: Binding(get: { model.webVerify },
                                               set: { newValue in
                model.webVerify = newValue
                model.onWebVerifyChanged?(newValue)
            }))
            .toggleStyle(.button)
            .help(model.webVerify
                  ? "Web verification is on. Anchora will search for current evidence and list the sources it used."
                  : "Off: answer from the PDF and general knowledge. On: search the web, verify claims, and show sources.")
        }
        .controlSize(.small)
        .lineLimit(1)
    }
}
