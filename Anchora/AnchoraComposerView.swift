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

struct AnchoraComposerView: View {

    @ObservedObject var model: AnchoraComposerModel

    /// The host gives this view a fixed height rather than letting it report an
    /// intrinsic one.  Nothing here wraps, so its height does not depend on its
    /// width -- but a fixed height keeps that guarantee in the layout instead of
    /// in an assumption about the content.
    static let height: CGFloat = 84.0

    var body: some View {
        VStack(spacing: 6.0) {
            quickActions
            askBar
            secondaryActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var askBar: some View {
        HStack(spacing: 8.0) {
            TextField(model.placeholder, text: $model.question)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.onSubmit?() }
            Button(model.isRequestInFlight ? "Stop" : "Send") {
                model.onSubmit?()
            }
            .keyboardShortcut(.return, modifiers: [])
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
