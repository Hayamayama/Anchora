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

    /// Bold, italic, `code`, links and bare URLs within a single block.
    ///
    /// This does not use `AttributedString(markdown:)`, because CommonMark's
    /// flanking rules make emphasis unusable next to Chinese text: in
    /// `**橫膈膜 (diaphragm)**收縮時` the closing run is preceded by punctuation
    /// and followed by a Han character, which disqualifies it from closing, so
    /// the whole thing renders as literal asterisks.  GitHub relaxed this for
    /// CJK in 2017; CommonMark has not.  The rule here is the relaxed one: a
    /// delimiter may open if what follows it is not whitespace, and may close
    /// if what precedes it is not whitespace.
    public static func inline(_ text: String) -> AttributedString {
        var result = AttributedString()
        appendInline(Array(text), into: &result, intents: [], depth: 0)
        return result
    }

    private static let emphasisDepthLimit = 4

    private static func appendInline(_ characters: [Character],
                                     into result: inout AttributedString,
                                     intents: InlinePresentationIntent,
                                     depth: Int) {
        var literal = ""

        func flushLiteral() {
            guard literal.isEmpty == false else { return }
            appendAutolinked(literal, into: &result, intents: intents)
            literal = ""
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]

            // A backslash escapes the next character, so a literal asterisk
            // survives.
            if character == "\\", index + 1 < characters.count {
                literal.append(characters[index + 1])
                index += 2
                continue
            }

            if character == "`", let span = codeSpan(characters, from: index) {
                flushLiteral()
                var code = AttributedString(span.text)
                code.inlinePresentationIntent = intents.union(.code)
                result.append(code)
                index = span.end
                continue
            }

            if character == "[", let link = linkSpan(characters, from: index) {
                flushLiteral()
                var inner = AttributedString()
                appendInline(Array(link.text), into: &inner, intents: intents, depth: depth + 1)
                if let url = URL(string: link.destination) {
                    inner.link = url
                }
                result.append(inner)
                index = link.end
                continue
            }

            if depth < emphasisDepthLimit,
               character == "*" || character == "_",
               let emphasis = emphasisSpan(characters, from: index) {
                flushLiteral()
                appendInline(Array(emphasis.text), into: &result,
                             intents: intents.union(emphasis.intent), depth: depth + 1)
                index = emphasis.end
                continue
            }

            literal.append(character)
            index += 1
        }
        flushLiteral()
    }

    // MARK: - Inline spans: pieces

    private static func codeSpan(_ characters: [Character], from start: Int) -> (text: String, end: Int)? {
        var run = 0
        while start + run < characters.count, characters[start + run] == "`" { run += 1 }
        var index = start + run
        while index < characters.count {
            if characters[index] == "`" {
                var closing = 0
                while index + closing < characters.count, characters[index + closing] == "`" { closing += 1 }
                if closing == run {
                    return (String(characters[(start + run)..<index]), index + closing)
                }
                index += closing
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func linkSpan(_ characters: [Character], from start: Int) -> (text: String, destination: String, end: Int)? {
        var index = start + 1
        var depth = 1
        while index < characters.count, depth > 0 {
            if characters[index] == "\\" { index += 2; continue }
            if characters[index] == "[" { depth += 1 }
            if characters[index] == "]" { depth -= 1 }
            index += 1
        }
        // A citation such as "[PDF p. 4]" has no destination and must stay text.
        guard depth == 0, index < characters.count, characters[index] == "(" else { return nil }
        let textEnd = index - 1
        index += 1
        let destinationStart = index
        while index < characters.count, characters[index] != ")" { index += 1 }
        guard index < characters.count else { return nil }
        return (String(characters[(start + 1)..<textEnd]),
                String(characters[destinationStart..<index]).trimmingCharacters(in: .whitespaces),
                index + 1)
    }

    private static func emphasisSpan(_ characters: [Character], from start: Int) -> (text: String, intent: InlinePresentationIntent, end: Int)? {
        let marker = characters[start]
        var run = 0
        while start + run < characters.count, characters[start + run] == marker { run += 1 }
        let width = min(run, 2)

        // The relaxed opening rule: something must follow, and it must not be
        // whitespace.
        let openEnd = start + width
        guard openEnd < characters.count, characters[openEnd].isWhitespace == false else { return nil }
        // "snake_case" is not emphasis.
        if marker == "_", start > 0, characters[start - 1].isLetter || characters[start - 1].isNumber { return nil }

        var index = openEnd
        while index < characters.count {
            if characters[index] == "\\" { index += 2; continue }
            guard characters[index] == marker else { index += 1; continue }
            var closing = 0
            while index + closing < characters.count, characters[index + closing] == marker { closing += 1 }
            // The relaxed closing rule: what precedes must not be whitespace.
            let precedingIsWhitespace = characters[index - 1].isWhitespace
            let underscoreInsideWord = marker == "_" && index + closing < characters.count
                && (characters[index + closing].isLetter || characters[index + closing].isNumber)
            if closing >= width, precedingIsWhitespace == false, underscoreInsideWord == false, index > openEnd {
                return (String(characters[openEnd..<index]),
                        width == 2 ? .stronglyEmphasized : .emphasized,
                        index + width)
            }
            index += closing
        }
        return nil
    }

    /// A bare http(s) URL in an answer should still be clickable.
    private static func appendAutolinked(_ text: String,
                                         into result: inout AttributedString,
                                         intents: InlinePresentationIntent) {
        func styled(_ piece: String) -> AttributedString {
            var attributed = AttributedString(piece)
            if intents.isEmpty == false {
                attributed.inlinePresentationIntent = intents
            }
            return attributed
        }

        guard text.contains("http"),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else {
            result.append(styled(text))
            return
        }

        let nsText = text as NSString
        var location = 0
        for match in detector.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let url = match.url else { continue }
            if match.range.location > location {
                result.append(styled(nsText.substring(with: NSRange(location: location, length: match.range.location - location))))
            }
            var link = styled(nsText.substring(with: match.range))
            link.link = url
            result.append(link)
            location = NSMaxRange(match.range)
        }
        if location < nsText.length {
            result.append(styled(nsText.substring(from: location)))
        }
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
