//
//  AnchoraStudyMap.swift
//  Anchora
//
//  Parses a study plan into navigable sections.
//
//  Unlike a paper map, which is pinned to eight known headings, a study plan
//  has as many blocks as the material needs, and their headings are written in
//  whatever language the reader has chosen.  So this splits on any heading at
//  all and keeps the order the model put them in -- that order is the answer.
//

import Foundation

@objc(AnchoraStudyMap)
public final class AnchoraStudyMap: NSObject {

    private static let headingPattern = #"(?m)^[ \t]{0,3}#{2,4}[ \t]+(\S.*?)[ \t]*$"#

    @objc public static func sections(fromResponse response: String, pageLabels: [String]) -> [AnchoraMapSection] {
        guard response.isEmpty == false else { return [] }

        let nsResponse = response as NSString
        let fullRange = NSRange(location: 0, length: nsResponse.length)
        guard let expression = try? NSRegularExpression(pattern: headingPattern) else { return [] }
        let headings = expression.matches(in: response, range: fullRange)

        // A plan that arrived without headings is still worth showing whole
        // rather than dropping on the floor.
        guard headings.isEmpty == false else {
            return [AnchoraMapSection(title: "Study map",
                                      text: response.trimmingCharacters(in: .whitespacesAndNewlines),
                                      pageIndexes: AnchoraPaperMap.pageIndexes(inText: response, pageLabels: pageLabels))]
        }

        var sections: [AnchoraMapSection] = []
        for (index, heading) in headings.enumerated() {
            let title = cleanedTitle(nsResponse.substring(with: heading.range(at: 1)))
            let start = NSMaxRange(heading.range)
            let end = (index + 1 < headings.count) ? headings[index + 1].range.location : nsResponse.length
            let text = nsResponse.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false else { continue }
            sections.append(AnchoraMapSection(title: title,
                                              text: text,
                                              pageIndexes: AnchoraPaperMap.pageIndexes(inText: text, pageLabels: pageLabels)))
        }
        return sections
    }

    /// A heading often arrives decorated (`## **1. Gas exchange**`).  The
    /// picker shows plain text, so the markers come off -- but the numbering
    /// stays, because it is the reading order.
    private static func cleanedTitle(_ raw: String) -> String {
        String(AnchoraMarkdown.inline(raw).characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
    }
}
