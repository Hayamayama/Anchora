//
//  AnchoraMarkdownText.swift
//  Anchora
//
//  Renders an answer's Markdown blocks.  Kept close to the previous plain-text
//  size so a formatted answer reads as the same voice, just with structure.
//

import SwiftUI

struct AnchoraMarkdownText: View {

    let markdown: String
    var bodySize: CGFloat = 13.5
    var foreground: Color = .primary

    private var blocks: [AnchoraMarkdownBlock] {
        AnchoraMarkdown.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            ForEach(blocks) { block in
                blockView(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: AnchoraMarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph:
            inlineText(block.text)

        case .heading(let level):
            inlineText(block.text, size: headingSize(level), weight: level <= 2 ? .bold : .semibold)
                .padding(.top, level <= 2 ? 6.0 : 3.0)

        case .listItem(let marker, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6.0) {
                Text(marker)
                    .font(.system(size: bodySize))
                    .foregroundStyle(foreground.opacity(0.65))
                    .monospacedDigit()
                inlineText(block.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, CGFloat(depth) * 14.0)

        case .quote:
            HStack(alignment: .top, spacing: 8.0) {
                Rectangle()
                    .fill(foreground.opacity(0.25))
                    .frame(width: 2.0)
                inlineText(block.text)
                    .italic()
            }
            .fixedSize(horizontal: false, vertical: true)

        case .codeBlock:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(size: bodySize - 1.0, design: .monospaced))
                    .foregroundStyle(foreground)
                    .textSelection(.enabled)
                    .padding(8.0)
            }
            .background(foreground.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6.0, style: .continuous))

        case .rule:
            Divider().opacity(0.5)
        }
    }

    private func inlineText(_ text: String,
                            size: CGFloat? = nil,
                            weight: Font.Weight = .regular) -> some View {
        let pointSize = size ?? bodySize
        return Text(styled(text, size: pointSize, weight: weight))
            .foregroundStyle(foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `Text` renders bold, italic and links from an AttributedString on its
    /// own, but a `code` span only carries a presentation intent — without this
    /// the backticks the prompt asks for would vanish with nothing to show for
    /// them.
    private func styled(_ text: String, size: CGFloat, weight: Font.Weight) -> AttributedString {
        var attributed = AnchoraMarkdown.inline(text)
        attributed.font = .system(size: size, weight: weight)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = .system(size: size - 0.5, weight: weight, design: .monospaced)
            attributed[run.range].foregroundColor = foreground.opacity(0.9)
        }
        return attributed
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return bodySize + 4.0
        case 2: return bodySize + 2.0
        case 3: return bodySize + 1.0
        default: return bodySize
        }
    }
}
