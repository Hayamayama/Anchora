//
//  AnchoraPaperMap.swift
//  Anchora
//
//  Parses a Scientific-profile paper map response into navigable sections and
//  resolves its [PDF p. X] citations to page indexes.  Pure text work: the
//  caller supplies the document's page labels, so this has no PDFKit
//  dependency and can be exercised without a document.
//

import Foundation

@objc(AnchoraPaperMap)
public final class AnchoraPaperMap: NSObject {

    private struct SectionDefinition {
        let title: String
        let pattern: String
    }

    private static let sectionDefinitions: [SectionDefinition] = [
        SectionDefinition(title: "Research problem and gap",
                          pattern: #"Research\s+problem\s+and\s+(?:knowledge\s+)?gap"#),
        SectionDefinition(title: "Objective",
                          pattern: #"Objective"#),
        SectionDefinition(title: "Main hypothesis / research question",
                          pattern: #"Main\s+hypothesis\s*/\s*research\s+question"#),
        SectionDefinition(title: "Study and experimental methods",
                          pattern: #"Study\s+and\s+experimental\s+methods"#),
        SectionDefinition(title: "Key figures and evidence",
                          pattern: #"Key\s+figures\s+and\s+evidence"#),
        SectionDefinition(title: "What the paper directly demonstrates",
                          pattern: #"What\s+the\s+paper\s+directly\s+demonstrates"#),
        SectionDefinition(title: "Authors’ interpretation",
                          pattern: #"Authors?[’']?\s*interpretation"#),
        SectionDefinition(title: "Limitations and unanswered questions",
                          // The "and" between the clauses used to be reachable
                          // only inside the "alternative explanations" branch, so
                          // the plain "Limitations and unanswered questions"
                          // heading the prompt asks for never matched and its
                          // text was swallowed by the preceding section.
                          pattern: #"Limitations?(?:,?\s*alternative\s+explanations?)?(?:,?\s*and)?\s*(?:what\s+remains\s+)?(?:unanswered\s+questions?|unproven)?"#),
    ]

    private static let citationPattern = #"\[PDF\s+p\.\s*([^\]]+)\]"#
    private static let pageRangePattern = #"^(\d+)\s*[-–]\s*(\d+)$"#

    private static let emptySectionText = "Not stated or unclear in the supplied paper."

    // MARK: - Citations

    /// Zero-based page indexes for every `[PDF p. X]` citation in `text`.
    @objc public static func pageIndexes(inText text: String, pageLabels: [String]) -> [NSNumber] {
        guard text.isEmpty == false,
              let citations = try? NSRegularExpression(pattern: citationPattern, options: [.caseInsensitive])
        else { return [] }

        let rangeExpression = try? NSRegularExpression(pattern: pageRangePattern)
        let nsText = text as NSString
        var indexes: [Int] = []

        func append(_ index: Int) {
            if indexes.contains(index) == false {
                indexes.append(index)
            }
        }

        for match in citations.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let labels = nsText.substring(with: match.range(at: 1))
            for rawLabel in labels.components(separatedBy: ",") {
                let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty { continue }

                if let matched = pageLabels.firstIndex(of: label) {
                    append(matched)
                    continue
                }

                // A citation may name a span ("[PDF p. 3-5]") rather than a
                // single label; expand it before falling back to a number.
                let nsLabel = label as NSString
                if let rangeMatch = rangeExpression?.firstMatch(in: label,
                                                                range: NSRange(location: 0, length: nsLabel.length)),
                   let first = Int(nsLabel.substring(with: rangeMatch.range(at: 1))),
                   let last = Int(nsLabel.substring(with: rangeMatch.range(at: 2))),
                   first > 0, last >= first, last <= pageLabels.count {
                    for pageNumber in first...last {
                        append(pageNumber - 1)
                    }
                    continue
                }

                if let pageNumber = Int(label), pageNumber > 0, pageNumber <= pageLabels.count {
                    append(pageNumber - 1)
                }
            }
        }

        return indexes.map(NSNumber.init(value:))
    }

    // MARK: - Sections

    /// Splits a paper map response on its expected H2 headings.  A response
    /// that does not follow the structure still yields one section, so the
    /// navigator never swallows an answer.
    @objc public static func sections(fromResponse response: String, pageLabels: [String]) -> [AnchoraMapSection] {
        guard response.isEmpty == false else { return [] }

        let nsResponse = response as NSString
        let fullRange = NSRange(location: 0, length: nsResponse.length)

        var headings: [(definition: SectionDefinition, range: NSRange)] = []
        for definition in sectionDefinitions {
            let pattern = #"(?im)^\s*(?:#{1,6}\s*)?(?:\d+\s*[.)]\s*)?"# + definition.pattern
                + #"(?:\s*\([^\n]*\))?\s*:?[ \t]*$"#
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: response, range: fullRange)
            else { continue }
            headings.append((definition, match.range))
        }
        headings.sort { $0.range.location < $1.range.location }

        var sections: [AnchoraMapSection] = []
        for (index, heading) in headings.enumerated() {
            let start = NSMaxRange(heading.range)
            let end = (index + 1 < headings.count) ? headings[index + 1].range.location : nsResponse.length
            var text = nsResponse.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                text = emptySectionText
            }
            sections.append(AnchoraMapSection(title: heading.definition.title,
                                                   text: text,
                                                   pageIndexes: pageIndexes(inText: text, pageLabels: pageLabels)))
        }

        if sections.isEmpty {
            sections.append(AnchoraMapSection(title: "Paper map response",
                                                   text: response,
                                                   pageIndexes: pageIndexes(inText: response, pageLabels: pageLabels)))
        }

        return sections
    }
}
