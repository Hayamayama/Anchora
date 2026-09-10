//
//  AnchoraPaperMapModel.swift
//  Anchora
//
//  State for the Paper Map navigator, plus the rich-text rendering of a
//  section: evidence labels are emphasised and every Source quote becomes a
//  link that selects the original sentence in the PDF.
//

import Foundation
import Combine
import SwiftUI

@objc(AnchoraPaperMapModel)
public final class AnchoraPaperMapModel: NSObject, ObservableObject {

    @Published public private(set) var sections: [AnchoraPaperMapSection] = []
    @Published public var selectedIndex: Int = 0
    @Published public private(set) var isExpanded: Bool = false

    /// Jump to a cited page.
    @objc public var onOpenPage: ((Int) -> Void)?
    /// Locate and select a Source quote on its cited page.
    @objc public var onOpenQuote: ((String, Int) -> Void)?
    /// Zero-based page index -> the label the reader sees in the PDF.
    @objc public var pageLabelProvider: ((Int) -> String)?
    /// Fired whenever `preferredHeight` may have changed, so the AppKit host
    /// can update the card's height constraint.
    @objc public var onLayoutChange: (() -> Void)?

    @objc public var isEmpty: Bool { sections.isEmpty }

    /// A collapsed map keeps a slim always-visible header, so "Hide" cannot
    /// strand the navigator with no way to bring it back.
    @objc public var preferredHeight: CGFloat {
        if sections.isEmpty { return 0.0 }
        return isExpanded ? 248.0 : 34.0
    }

    public var selectedSection: AnchoraPaperMapSection? {
        sections.indices.contains(selectedIndex) ? sections[selectedIndex] : nil
    }

    // MARK: - Mutation

    @objc public func present(_ sections: [AnchoraPaperMapSection]) {
        guard sections.isEmpty == false else { return }
        self.sections = sections
        selectedIndex = 0
        isExpanded = true
        onLayoutChange?()
    }

    @objc public func clear() {
        sections = []
        selectedIndex = 0
        isExpanded = false
        onLayoutChange?()
    }

    public func setExpanded(_ expanded: Bool) {
        guard sections.isEmpty == false else { return }
        isExpanded = expanded
        onLayoutChange?()
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
    public func attributedDetail(for section: AnchoraPaperMapSection, pageLabels: [String]) -> AttributedString {
        let text = section.text
        var attributed = AttributedString(text)
        attributed.font = .system(size: 12.5)
        attributed.foregroundColor = .primary

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        func range(_ nsRange: NSRange) -> Range<AttributedString.Index>? {
            Range(nsRange, in: attributed)
        }

        for label in AnchoraPaperMapModel.evidenceLabels {
            let pattern = #"(?im)^\s*(?:[-•]\s*)?"# + NSRegularExpression.escapedPattern(for: label) + #"\s*:?[ \t]*"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: text, range: fullRange) {
                guard let attributedRange = range(match.range) else { continue }
                attributed[attributedRange].font = .system(size: 12.5, weight: .bold)
                attributed[attributedRange].foregroundColor = Color(nsColor: .controlAccentColor)
            }
        }

        if let expression = try? NSRegularExpression(pattern: AnchoraPaperMapModel.quotePattern) {
            for match in expression.matches(in: text, range: fullRange) {
                let quote = nsText.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
                let citation = "[PDF p. \(nsText.substring(with: match.range(at: 2)))]"
                let pageIndexes = AnchoraPaperMap.pageIndexes(inText: citation, pageLabels: pageLabels)
                guard quote.isEmpty == false,
                      let pageIndex = pageIndexes.first?.intValue,
                      let url = AnchoraPaperMapModel.quoteURL(quote: quote, pageIndex: pageIndex),
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
        guard url.scheme == AnchoraPaperMapModel.quoteScheme else { return false }
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
