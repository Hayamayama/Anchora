//
//  AnchoraChatView.swift
//  Anchora
//
//  The chat transcript.  This replaces a hand-measured NSStackView of
//  NSTextField bubbles: wrapped text height, bubble growth with the sidebar
//  width, and the answer/source-footer separation are all layout the
//  framework now owns.
//

import SwiftUI

struct AnchoraChatView: View {

    @ObservedObject var model: AnchoraChatModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 9.0) {
                    ForEach(model.messages) { message in
                        AnchoraChatBubble(message: message,
                                          isLatest: message.id == model.messages.last?.id,
                                          model: model)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 10.0)
                .padding(.horizontal, 8.0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.revision) {
                guard let last = model.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct AnchoraChatBubble: View {

    let message: AnchoraChatMessage
    /// The newest answer keeps its actions on screen; older ones reveal them on
    /// hover.  A row under every answer is noise in a transcript that is mostly
    /// read, but hidden everywhere it would never be found.
    let isLatest: Bool
    @ObservedObject var model: AnchoraChatModel

    @State private var isHovering = false
    @State private var didCopy = false

    private var isUser: Bool { message.kind == .user }

    /// Actions belong to a finished answer.  A user turn has nothing to pin,
    /// and a bubble still showing a request phase has nothing to copy.
    private var showsActions: Bool {
        message.kind == .assistant && message.isPlaceholder == false && message.text.isEmpty == false
    }

    private var background: Color {
        isUser ? Color(nsColor: .selectedContentBackgroundColor) : Color(nsColor: .controlBackgroundColor)
    }

    private var bodyColor: Color {
        isUser ? Color(nsColor: .alternateSelectedControlTextColor) : .primary
    }

    private var senderColor: Color {
        isUser ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.82) : .secondary
    }

    var body: some View {
        HStack(spacing: 0.0) {
            // A user turn stays deliberately compact and right-aligned; an
            // answer is meant to be read as a document and takes the width.
            if isUser { Spacer(minLength: 40.0) }

            VStack(alignment: .leading, spacing: 3.0) {
                Text(message.senderName)
                    .font(.system(size: 10.0, weight: .bold))
                    .foregroundStyle(senderColor)

                // Only model output is Markdown.  A user turn, a request-phase
                // placeholder and the web-source list are strings we build
                // ourselves, and running the source list through the parser
                // would join its lines into one paragraph.
                Group {
                    if message.isPlaceholder || isUser || message.kind == .webSources {
                        Text(message.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(message.isPlaceholder ? bodyColor.opacity(0.7) : bodyColor)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        AnchoraMarkdownText(markdown: message.text, foreground: bodyColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsActions {
                    actions
                        .padding(.top, 6.0)
                        .opacity(isLatest || isHovering ? 1.0 : 0.0)
                }

                if let label = message.sourceLabel, let pageIndex = message.sourcePageIndex {
                    Button {
                        model.onOpenPage?(pageIndex)
                    } label: {
                        Text("↗ \(label)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 5.0)
                    .help("Jump to the PDF page used for this answer")
                }
            }
            .padding(.horizontal, 12.0)
            .padding(.vertical, 8.0)
            .frame(maxWidth: isUser ? nil : .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 14.0, style: .continuous))

            if isUser == false { Spacer(minLength: 0.0) }
        }
        .onHover { isHovering = $0 }
    }

    private var actions: some View {
        HStack(spacing: 10.0) {
            action(didCopy ? "Copied" : "Copy", help: "Copy this answer as plain text") {
                model.onCopy?(message.text)
                didCopy = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    didCopy = false
                }
            }
            if let turn = message.turn, turn.canPin {
                action("Pin as note", help: "Add this answer to the PDF as a compact anchored note") {
                    model.onPinAnchor?(turn)
                }
                action("Pin as text", help: "Add this answer to the PDF as a text note visible on the page") {
                    model.onPinTextNote?(turn)
                }
            }
            Spacer(minLength: 0.0)
        }
    }

    private func action(_ title: String, help: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
