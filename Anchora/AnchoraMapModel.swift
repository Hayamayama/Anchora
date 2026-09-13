//
//  AnchoraMapModel.swift
//  Anchora
//
//  State for the Paper Map navigator, plus the rich-text rendering of a
//  section: evidence labels are emphasised and every Source quote becomes a
//  link that selects the original sentence in the PDF.
//

import Foundation
import Combine
import SwiftUI

@objc(AnchoraMapModel)
public final class AnchoraMapModel: NSObject, ObservableObject {

    @Published public private(set) var sections: [AnchoraMapSection] = []
    @Published public private(set) var kind: AnchoraMapKind = .none

    /// What this map is, shown on the card.
    public var title: String {
        switch kind {
        case .study: return "STUDY MAP"
        case .paper: return "PAPER MAP"
        case .none: return "MAP"
        }
    }

    /// The tab's label, which has to stay short enough to sit in a strip.
    public var shortTitle: String {
        switch kind {
        case .study: return "Study map"
        case .paper: return "Paper map"
        case .none: return "Map"
        }
    }

    public var legend: String {
        switch kind {
        case .study: return "Pick a block, then jump to its pages"
        case .paper: return "Click a Source quote to highlight it in the PDF"
        case .none: return ""
        }
    }

    /// A study plan is ordinary prose and lists, so it reads far better as
    /// rendered Markdown.  A paper map is not: its body carries the evidence
    /// labels and Source quote links, whose ranges are computed against the
    /// raw text and would not survive being reflowed.
    public var rendersMarkdown: Bool { kind == .study }
    @Published public var selectedIndex: Int = 0

    /// Jump to a cited page.
    @objc public var onOpenPage: ((Int) -> Void)?
    /// Locate and select a Source quote on its cited page.
    @objc public var onOpenQuote: ((String, Int) -> Void)?
    /// Zero-based page index -> the label the reader sees in the PDF.
    @objc public var pageLabelProvider: ((Int) -> String)?

    @objc public var isEmpty: Bool { sections.isEmpty }

    public var selectedSection: AnchoraMapSection? {
        sections.indices.contains(selectedIndex) ? sections[selectedIndex] : nil
    }

    // MARK: - Mutation

    @objc public func present(_ sections: [AnchoraMapSection], kind: AnchoraMapKind) {
        guard sections.isEmpty == false else { return }
        self.sections = sections
        self.kind = kind
        selectedIndex = 0
    }

    @objc public func clear() {
        sections = []
        kind = .none
        selectedIndex = 0
    }

    // MARK: - Page labels

    public func pageLabel(for pageIndex: Int) -> String {
        let label = pageLabelProvider?(pageIndex) ?? ""
        return label.isEmpty ? String(pageIndex + 1) : label
    }

    // MARK: - Section rendering

    private static let evidenceLabels = [
        "Direct evidence",
        "Author interpretation",
        "Reasonable inference",
        "Unproven / limitation",
        "Not stated or unclear",
    ]

    private static let quotePattern =
        #"(?im)^\s*(?:[-•]\s*)?Source quote\s*:\s*[“"]?(.+?)[”"]?\s*\[PDF\s+p\.\s*([^\]]+)\]"#

    /// Builds the displayed section text: evidence labels emphasised, and each
    /// Source quote turned into an `anchora-pdf:` link carrying its own text
    /// and cited page.
    public func attributedDetail(for section: AnchoraMapSection, pageLabels: [String]) -> AttributedString {
        let text = section.text
        var attributed = AttributedString(text)
        attributed.font = .system(size: 12.5)
        attributed.foregroundColor = .primary

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        func range(_ nsRange: NSRange) -> Range<AttributedString.Index>? {
            Range(nsRange, in: attributed)
        }

        for label in AnchoraMapModel.evidenceLabels {
            let pattern = #"(?im)^\s*(?:[-•]\s*)?"# + NSRegularExpression.escapedPattern(for: label) + #"\s*:?[ \t]*"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: text, range: fullRange) {
                guard let attributedRange = range(match.range) else { continue }
                attributed[attributedRange].font = .system(size: 12.5, weight: .bold)
                attributed[attributedRange].foregroundColor = Color(nsColor: .controlAccentColor)
            }
        }

        if let expression = try? NSRegularExpression(pattern: AnchoraMapModel.quotePattern) {
            for match in expression.matches(in: text, range: fullRange) {
                let quote = nsText.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
                let citation = "[PDF p. \(nsText.substring(with: match.range(at: 2)))]"
                let pageIndexes = AnchoraPaperMap.pageIndexes(inText: citation, pageLabels: pageLabels)
                guard quote.isEmpty == false,
                      let pageIndex = pageIndexes.first?.intValue,
                      let url = AnchoraMapModel.quoteURL(quote: quote, pageIndex: pageIndex),
                      let attributedRange = range(match.range(at: 1))
                else { continue }
                attributed[attributedRange].link = url
                attributed[attributedRange].underlineStyle = .single
                attributed[attributedRange].foregroundColor = Color(nsColor: .controlAccentColor)
            }
        }

        return attributed
    }

    // MARK: - Quote links

    private static let quoteScheme = "anchora-pdf"

    static func quoteURL(quote: String, pageIndex: Int) -> URL? {
        guard let data = quote.data(using: .utf8) else { return nil }
        // URL-safe base64 so the payload survives inside a path component.
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "\(quoteScheme)://quote/\(pageIndex)/\(encoded)")
    }

    /// Handles a click on a rendered quote link.  Returns false for anything
    /// that is not one of our own links, so real URLs still open normally.
    func handle(url: URL) -> Bool {
        guard url.scheme == AnchoraMapModel.quoteScheme else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, let pageIndex = Int(components[0]) else { return true }

        var encoded = components[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard let data = Data(base64Encoded: encoded),
              let quote = String(data: data, encoding: .utf8)
        else { return true }

        onOpenQuote?(quote, pageIndex)
        return true
    }
}
