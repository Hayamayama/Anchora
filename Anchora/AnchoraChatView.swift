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
                        AnchoraChatBubble(message: message, openPage: model.onOpenPage)
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
    let openPage: ((Int) -> Void)?

    private var isUser: Bool { message.kind == .user }

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

                if let label = message.sourceLabel, let pageIndex = message.sourcePageIndex {
                    Button {
                        openPage?(pageIndex)
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
    }
}
