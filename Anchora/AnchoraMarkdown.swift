//
//  AnchoraMarkdown.swift
//  Anchora
//
//  Answers arrive as Markdown.  SwiftUI's `AttributedString(markdown:)` only
//  understands *inline* syntax — a heading, a bullet or a code fence is parsed
//  into a presentation intent that `Text` then discards, so "- item" would
//  render with its marker silently missing.  This splits an answer into blocks
//  the view can lay out itself, and leaves only inline spans to AttributedString.
//

import Foundation

public struct AnchoraMarkdownBlock: Identifiable {

    public enum Kind: Equatable {
        case paragraph
        case heading(level: Int)
        /// `marker` is the bullet or number already rendered for the reader.
        case listItem(marker: String, depth: Int)
        case quote
        case codeBlock(language: String?)
        case rule
    }

    /// The block's position in the answer, not a fresh identity per parse.  A
    /// streaming answer is re-parsed on every flush; a new UUID each time would
    /// make SwiftUI tear down and rebuild every block eight times a second, and
    /// would drop the reader's text selection while an answer was still arriving.
    public let id: Int
    public let kind: Kind
    public let text: String
}

@objc(AnchoraMarkdown)
public final class AnchoraMarkdown: NSObject {

    // MARK: - Block splitting

    private static let headingPattern = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.*)$"#)
    private static let bulletPattern = try? NSRegularExpression(pattern: #"^(\s*)[-*+]\s+(.*)$"#)
    private static let orderedPattern = try? NSRegularExpression(pattern: #"^(\s*)(\d{1,3})[.)]\s+(.*)$"#)
    private static let quotePattern = try? NSRegularExpression(pattern: #"^\s{0,3}>\s?(.*)$"#)
    private static let rulePattern = try? NSRegularExpression(pattern: #"^\s{0,3}([-*_])\s*(\1\s*){2,}$"#)

    private static func match(_ expression: NSRegularExpression?, _ line: String) -> NSTextCheckingResult? {
        guard let expression else { return nil }
        return expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in line: String) -> String {
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : (line as NSString).substring(with: range)
    }

    public static func blocks(from markdown: String) -> [AnchoraMarkdownBlock] {
        var blocks: [AnchoraMarkdownBlock] = []
        var paragraph: [String] = []

        func append(_ kind: AnchoraMarkdownBlock.Kind, _ text: String) {
            blocks.append(AnchoraMarkdownBlock(id: blocks.count, kind: kind, text: text))
        }

        func flushParagraph() {
            guard paragraph.isEmpty == false else { return }
            append(.paragraph, paragraph.joined(separator: " "))
            paragraph.removeAll()
        }

        let lines = markdown.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A fenced block runs to its closing fence, or — while an answer is
            // still streaming — to the end of what has arrived so far.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count,
                      lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") == false {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                append(.codeBlock(language: language.isEmpty ? nil : language), code.joined(separator: "\n"))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if match(rulePattern, line) != nil {
                flushParagraph()
                append(.rule, "")
                index += 1
                continue
            }

            if let heading = match(headingPattern, line) {
                flushParagraph()
                let level = group(heading, 1, in: line).count
                append(.heading(level: level), group(heading, 2, in: line))
                index += 1
                continue
            }

            if let bullet = match(bulletPattern, line) {
                flushParagraph()
                let depth = min(group(bullet, 1, in: line).count / 2, 3)
                append(.listItem(marker: "•", depth: depth), group(bullet, 2, in: line))
                index += 1
                continue
            }

            if let ordered = match(orderedPattern, line) {
                flushParagraph()
                let depth = min(group(ordered, 1, in: line).count / 2, 3)
                append(.listItem(marker: group(ordered, 2, in: line) + ".", depth: depth), group(ordered, 3, in: line))
                index += 1
                continue
            }

            if let quote = match(quotePattern, line) {
                flushParagraph()
                append(.quote, group(quote, 1, in: line))
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    // MARK: - Inline spans

    /// Bold, italic, `code` and links within a single block.  A half-written
    /// span mid-stream (`**bold` with no closing marker) is left as literal
    /// text rather than discarded.
    public static func inline(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - Plain text

    /// Markdown flattened for somewhere that cannot render it — a pinned PDF
    /// note, which is plain text in the PDF itself.
    @objc public static func plainText(from markdown: String) -> String {
        var lines: [String] = []
        for block in blocks(from: markdown) {
            let inlineText = String(inline(block.text).characters)
            switch block.kind {
            case .paragraph:
                lines.append(inlineText)
            case .heading:
                lines.append(inlineText)
            case .listItem(let marker, let depth):
                lines.append(String(repeating: "    ", count: depth) + marker + " " + inlineText)
            case .quote:
                lines.append("“" + inlineText + "”")
            case .codeBlock:
                lines.append(block.text)
            case .rule:
                lines.append("—")
            }
        }
        return lines.joined(separator: "\n")
    }
}
