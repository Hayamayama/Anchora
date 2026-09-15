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

    /// The one heading `AnchoraPrompts.studyMapPrompt` requires in this exact
    /// English spelling regardless of response language -- every other
    /// heading is left to the model, but this one has to be found again by
    /// the app, so it cannot be.
    @objc public static let selfTestHeading = "Self-test questions"

    private static let headingPattern = #"(?m)^[ \t]{0,3}#{2,4}[ \t]+(\S.*?)[ \t]*$"#
    private static let questionLinePattern = #"(?m)^[ \t]{0,3}(?:[0-9]+[.)]|[-•*])[ \t]+(\S.*?)[ \t]*$"#

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

    /// Which section, if any, is the self-test -- matched by its fixed
    /// heading rather than by position, since a model that skips the closing
    /// sections (or orders them differently) should not have some other
    /// section mistaken for it.
    @objc(selfTestSectionIndexIn:)
    public static func selfTestSectionIndex(in sections: [AnchoraMapSection]) -> Int {
        sections.firstIndex { $0.title.caseInsensitiveCompare(selfTestHeading) == .orderedSame }
            .map { NSNumber(value: $0) }?.intValue ?? NSNotFound
    }

    /// Pulls the individual questions out of the self-test section's text --
    /// one per numbered or bulleted line -- so each can be checked off on its
    /// own rather than the section being one long block to mark done at once.
    @objc(selfTestQuestionsFromSectionText:)
    public static func selfTestQuestions(fromSectionText text: String) -> [String] {
        guard text.isEmpty == false,
              let expression = try? NSRegularExpression(pattern: questionLinePattern)
        else { return [] }
        let nsText = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let questions = matches.map {
            nsText.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A self-test section is short prose without any numbered or bulleted
        // line often enough (the model wrote plain sentences instead) that
        // falling back to the whole section, as one item, beats showing an
        // empty checklist for a section that plainly has content.
        if questions.isEmpty {
            let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return whole.isEmpty ? [] : [whole]
        }
        return questions
    }
}
