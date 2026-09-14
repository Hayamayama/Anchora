import Foundation
import CoreGraphics
import PDFKit

// Behavioural tests for Anchora's Swift core: the paper map parser, the
// prompt/parser contract, settings persistence, and the chat transcript model.
// These files are deliberately free of AppKit and Skim types, so the suite
// compiles and runs without the app.
//
// Run:
// Tools/run-anchora-tests.sh

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ what: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if condition() == false {
        failures += 1
        FileHandle.standardError.write(Data("FAIL  \(what)  (line \(line))\n".utf8))
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String, line: UInt = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        FileHandle.standardError.write(Data("FAIL  \(what)\n      expected: \(expected)\n      actual:   \(actual)\n      (line \(line))\n".utf8))
    }
}

let labels = (1...20).map(String.init)

// MARK: - Paper map: section splitting

func testAllHeadingsSplit() {
    let response = """
    ## Research problem and knowledge gap
    a
    ## Objective
    b
    ## Main hypothesis / research question
    c
    ## Study and experimental methods
    d
    ## Key figures and evidence
    e
    ## What the paper directly demonstrates
    f
    ## Authors' interpretation
    g
    ## Limitations and unanswered questions
    h
    """
    let sections = AnchoraPaperMap.sections(fromResponse: response, pageLabels: labels)
    expectEqual(sections.count, 8, "all eight headings split into their own sections")
    expectEqual(sections.map(\.text), ["a", "b", "c", "d", "e", "f", "g", "h"],
                "each section keeps only its own body")
}

/// The bug this guards: the "and" between clauses was reachable only inside the
/// "alternative explanations" branch, so the plain heading never matched and its
/// text was swallowed by the preceding section.
func testLimitationsHeadingVariants() {
    for heading in ["Limitations and unanswered questions",
                    "Limitations, alternative explanations, and what remains unproven",
                    "Limitations"] {
        let sections = AnchoraPaperMap.sections(fromResponse: "## Objective\nb\n## \(heading)\nh",
                                                pageLabels: labels)
        expectEqual(sections.count, 2, "heading variant splits: \(heading)")
        expectEqual(sections.last?.text ?? "", "h", "heading variant keeps its body: \(heading)")
    }
}

func testUnstructuredResponseStillYieldsOneSection() {
    let sections = AnchoraPaperMap.sections(fromResponse: "just a plain answer [PDF p. 7]", pageLabels: labels)
    expectEqual(sections.count, 1, "an unstructured answer is never swallowed")
    expectEqual(sections[0].pageIndexes.map(\.intValue), [6], "fallback section still resolves citations")
}

func testEmptySectionGetsPlaceholder() {
    let sections = AnchoraPaperMap.sections(fromResponse: "## Objective\n\n## Key figures and evidence\ne",
                                            pageLabels: labels)
    expectEqual(sections.count, 2, "an empty section is still listed")
    expect(sections[0].text.contains("Not stated or unclear"), "an empty section gets its placeholder text")
}

// MARK: - Paper map: citation resolution

func testCitationResolution() {
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "claim [PDF p. 3]", pageLabels: labels).map(\.intValue), [2],
                "a single citation resolves to a zero-based index")
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "claim [PDF p. 4-6]", pageLabels: labels).map(\.intValue), [3, 4, 5],
                "a page range expands")
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "a [PDF p. 2, 5]", pageLabels: labels).map(\.intValue), [1, 4],
                "a comma-separated citation resolves each label")
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "a [PDF p. 3] b [PDF p. 3]", pageLabels: labels).map(\.intValue), [2],
                "a repeated citation is listed once")
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "a [PDF p. 99]", pageLabels: labels).count, 0,
                "a page beyond the document is dropped rather than clamped")
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "no citation here", pageLabels: labels).count, 0,
                "text without citations resolves to nothing")
}

/// Documents with roman-numeral or offprint labels must resolve by label, not
/// by position.
func testCitationResolvesNonNumericLabels() {
    let roman = ["i", "ii", "iii", "S1", "S2"]
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "a [PDF p. iii]", pageLabels: roman).map(\.intValue), [2],
                "a roman-numeral label resolves by label")
    expectEqual(AnchoraPaperMap.pageIndexes(inText: "a [PDF p. S2]", pageLabels: roman).map(\.intValue), [4],
                "a supplementary label resolves by label")
}

// MARK: - The prompt/parser contract

/// The paper map prompt names the exact headings the navigator parses back out.
/// If the two drift, a whole section silently disappears into its neighbour --
/// which is precisely how the Limitations bug survived.
func testPromptHeadingsAreParseable() {
    let prompt = AnchoraPrompts.paperMapPrompt
    // Headings are listed separated by ";", and the last one ends the sentence.
    let headings = prompt.components(separatedBy: "## ")
        .dropFirst()
        .map { segment -> String in
            segment.components(separatedBy: ";")[0]
                .components(separatedBy: ". ")[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { $0.isEmpty == false }

    expectEqual(headings.count, 8, "the prompt still asks for eight headings")

    let response = headings.map { "## \($0)\nbody of \($0)" }.joined(separator: "\n")
    let sections = AnchoraPaperMap.sections(fromResponse: response, pageLabels: labels)
    expectEqual(sections.count, headings.count,
                "every heading the prompt asks for is one the parser recognises")
    for heading in headings where sections.contains(where: { $0.text == "body of \(heading)" }) == false {
        failures += 1
        FileHandle.standardError.write(Data("FAIL  prompt heading not parsed: \(heading)\n".utf8))
    }
    checks += 1
}

// MARK: - Settings

func testSettings() {
    let suite = UserDefaults(suiteName: "AnchoraCoreTests")!
    suite.removePersistentDomain(forName: "AnchoraCoreTests")
    let settings = AnchoraSettings(defaults: suite)

    expectEqual(settings.modelIdentifier, AnchoraSettings.defaultModelIdentifier,
                "an unset model falls back to the safe default")
    settings.modelIdentifier = "definitely-not-a-real-model"
    expectEqual(settings.modelIdentifier, AnchoraSettings.defaultModelIdentifier,
                "a model outside the curated list is rejected")
    settings.modelIdentifier = "gpt-5.6-terra"
    expectEqual(settings.modelIdentifier, "gpt-5.6-terra", "a curated model is stored")

    suite.set("gpt-4-removed-since", forKey: "Anchora.AIModel")
    expectEqual(settings.modelIdentifier, AnchoraSettings.defaultModelIdentifier,
                "a stored model that has left the list falls back rather than failing the request")

    expectEqual(settings.readingProfile, .study, "reading profile defaults to Study")
    expectEqual(settings.responseLanguage, .traditionalChinese, "response language defaults to Traditional Chinese")
    settings.readingProfile = .scientific
    expect(AnchoraSettings(defaults: suite).isScientific, "the reading profile survives a new instance")

    suite.removePersistentDomain(forName: "AnchoraCoreTests")
}

func testPromptsFollowSettings() {
    let chinese = AnchoraPrompts.systemInstructions(profile: .study, language: .traditionalChinese, webVerification: false)
    let english = AnchoraPrompts.systemInstructions(profile: .study, language: .english, webVerification: false)
    expect(chinese.contains("Traditional Chinese"), "the Chinese setting reaches the instructions")
    expect(english.contains("clear English"), "the English setting reaches the instructions")
    expect(chinese.contains("web search") == false, "web search is not mentioned when the toggle is off")

    let verified = AnchoraPrompts.systemInstructions(profile: .scientific, language: .english, webVerification: true)
    expect(verified.contains("web search"), "enabling Web verify reaches the instructions")
    expect(verified.contains("not stated or unclear"), "the scientific profile keeps its hedging rule")

    expect(AnchoraPrompts.quickActionTitles(profile: .scientific).count == 3, "the scientific row is three buttons")
    expect(AnchoraPrompts.quickActionTitles(profile: .study).count == 3, "and so is the study row")
    expectEqual(AnchoraPrompts.documentSummaryPrompt(profile: .scientific), AnchoraPrompts.paperMapPrompt,
                "Summarize-this-PDF in Scientific is the paper map prompt")

    let prompt = AnchoraPrompts.userPrompt(question: "Why?", sourceText: "some text", sourceDescription: "p. 3")
    expect(prompt.contains("p. 3") && prompt.contains("some text") && prompt.contains("Why?"),
           "a prompt with context carries page, context, and question")
    expectEqual(AnchoraPrompts.userPrompt(question: "Why?", sourceText: nil, sourceDescription: "p. 3"),
                "Question: Why?", "a follow-up without context is just the question")
}

// MARK: - Chat transcript

func testChatStreamingLifecycle() {
    let model = AnchoraChatModel()
    model.appendUserMessage("Explain this")
    model.beginStreamingMessage(status: "Uploading PDF to Anchora…", sourceLabel: "p. 4", sourcePageIndex: NSNumber(value: 3), turn: nil)
    expectEqual(model.messages.count, 2, "the streaming bubble exists before the first delta")
    expect(model.messages[1].isPlaceholder, "the streaming bubble starts as a placeholder")

    model.updateStreamingStatus("Anchora is reading the document…")
    expectEqual(model.messages[1].text, "Anchora is reading the document…", "status updates land in the placeholder")

    model.appendStreamedText("Hello")
    expect(model.messages[1].isPlaceholder == false, "the first delta clears the placeholder")
    expectEqual(model.messages[1].text, "Hello", "the first delta replaces the status rather than appending to it")
    model.appendStreamedText(" world")
    expectEqual(model.messages[1].text, "Hello world", "later deltas append")
    expectEqual(model.messages[1].sourceLabel, "p. 4", "the source chip survives streaming")

    model.updateStreamingStatus("late status")
    expectEqual(model.messages[1].text, "Hello world", "a late status never overwrites real output")
}

func testChatStopAndError() {
    let model = AnchoraChatModel()
    model.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil, turn: nil)
    model.replaceStreamingMessage(with: "Stopped.")
    expectEqual(model.messages.count, 1, "stopping before any output reuses the placeholder bubble")
    expectEqual(model.messages[0].text, "Stopped.", "the placeholder shows why it stopped")

    let partial = AnchoraChatModel()
    partial.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil, turn: nil)
    partial.appendStreamedText("half an answer")
    partial.replaceStreamingMessage(with: "Network error: timed out")
    expectEqual(partial.messages.count, 2, "an error after partial output keeps the partial answer")
    expectEqual(partial.messages[0].text, "half an answer", "the partial answer is not destroyed")
}

func testChatPaperMapRemovesItsBubble() {
    let model = AnchoraChatModel()
    model.appendUserMessage("Build Paper Map")
    model.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil, turn: nil)
    model.appendStreamedText("## Objective\nlong paper map text")
    model.removeStreamingMessage()
    expectEqual(model.messages.count, 1, "a paper map's raw text leaves the transcript")
    expectEqual(model.messages[0].kind, .user, "the question that produced it stays")
}

/// Clear chat cancels the turn, but a delta already in flight can still arrive.
func testChatSurvivesClearMidStream() {
    let model = AnchoraChatModel()
    model.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil, turn: nil)
    model.clear()
    model.appendStreamedText("a delta that lost its bubble")
    model.updateStreamingStatus("a status that lost its bubble")
    model.replaceStreamingMessage(with: "Stopped.")
    expectEqual(model.messages.count, 1, "a late turn after Clear chat appends rather than crashing")
    expectEqual(model.messages[0].text, "Stopped.", "the late message is still shown")
}

func testChatHintDeduplication() {
    let model = AnchoraChatModel()
    let hint = "Select text, Option-drag for OCR"
    expect(model.containsText(hint) == false, "an empty transcript contains no hint")
    model.appendAssistantMessage(hint + ", or Command-Option-drag to send an image region.")
    expect(model.containsText(hint), "the hint is found once written, so it is not repeated")
}

func testChatSenderNames() {
    let model = AnchoraChatModel()
    model.appendUserMessage("q")
    model.appendAssistantMessage("a")
    model.appendWebSourcesMessage("• https://example.org")
    expectEqual(model.messages.map(\.senderName), ["You", "Anchora", "Web sources"], "each kind labels itself")
}

// MARK: - Markdown

func testMarkdownBlockKinds() {
    let blocks = AnchoraMarkdown.blocks(from: """
    ## Findings
    A paragraph that wraps
    across two source lines.

    - first point
    - second point
    1. step one
    2. step two
    > a quoted sentence
    ---
    ```swift
    let x = 1
    ```
    """)
    let kinds = blocks.map(\.kind)
    expectEqual(kinds.count, 9, "every block is recognised")
    expectEqual(kinds[0], .heading(level: 2), "## becomes a level-2 heading")
    expectEqual(blocks[0].text, "Findings", "the heading marker is not part of the text")
    expectEqual(kinds[1], .paragraph, "prose becomes a paragraph")
    expectEqual(blocks[1].text, "A paragraph that wraps across two source lines.",
                "soft-wrapped source lines join into one paragraph")
    expectEqual(kinds[2], .listItem(marker: "•", depth: 0), "- becomes a bullet")
    expectEqual(blocks[2].text, "first point", "the bullet marker is not part of the text")
    expectEqual(kinds[4], .listItem(marker: "1.", depth: 0), "1. keeps its own number")
    expectEqual(kinds[5], .listItem(marker: "2.", depth: 0), "an ordered list is not renumbered from one")
    expectEqual(kinds[6], .quote, "> becomes a quote")
    expectEqual(kinds[7], .rule, "--- becomes a rule")
    expectEqual(kinds[8], .codeBlock(language: "swift"), "a fence keeps its language")
    expectEqual(blocks[8].text, "let x = 1", "code keeps its content without the fences")
}

func testMarkdownNestedList() {
    let blocks = AnchoraMarkdown.blocks(from: "- top\n  - nested\n    - deeper")
    expectEqual(blocks.map(\.kind), [.listItem(marker: "•", depth: 0),
                                    .listItem(marker: "•", depth: 1),
                                    .listItem(marker: "•", depth: 2)],
                "indentation becomes nesting depth")
}

/// Every flush during streaming re-parses a partial answer, so half-written
/// syntax must degrade rather than throw away text.
func testMarkdownHandlesPartialStreamedText() {
    let unclosedFence = AnchoraMarkdown.blocks(from: "## Title\n```swift\nlet x = 1")
    expectEqual(unclosedFence.count, 2, "an unclosed fence still yields its block")
    expectEqual(unclosedFence[1].text, "let x = 1", "an unclosed fence keeps the code that has arrived")

    let unclosedBold = AnchoraMarkdown.inline("this is **half a bold span")
    expect(String(unclosedBold.characters).contains("half a bold span"),
           "an unclosed bold span keeps its text")

    expectEqual(AnchoraMarkdown.blocks(from: "").count, 0, "an empty answer yields no blocks")
    expectEqual(AnchoraMarkdown.blocks(from: "#").count, 1, "a lone hash is prose, not a heading")
}

/// A re-parse must not change block identity, or SwiftUI rebuilds the whole
/// answer on every flush and drops the reader's selection.
func testMarkdownBlockIdentityIsStable() {
    let full = "## A\n- one\n- two\n\nprose"
    let firstPass = AnchoraMarkdown.blocks(from: full)
    let secondPass = AnchoraMarkdown.blocks(from: full)
    expectEqual(firstPass.map(\.id), secondPass.map(\.id), "re-parsing the same answer keeps block ids")

    let growing = AnchoraMarkdown.blocks(from: full + "\n\nmore prose")
    expectEqual(Array(growing.map(\.id).prefix(firstPass.count)), firstPass.map(\.id),
                "blocks already on screen keep their ids as an answer grows")
}

/// The citation format has to survive Markdown parsing untouched, because the
/// Paper Map resolves it afterwards.
func testMarkdownPreservesCitations() {
    let blocks = AnchoraMarkdown.blocks(from: "- **Direct evidence:** the assay failed [PDF p. 4]")
    expectEqual(blocks.count, 1, "a bold-led bullet is still one bullet")
    let rendered = String(AnchoraMarkdown.inline(blocks[0].text).characters)
    expect(rendered.contains("[PDF p. 4]"), "a citation is not consumed as a Markdown link")
    expect(rendered.contains("**") == false, "the bold markers themselves are consumed")
    expect(rendered.contains("Direct evidence:"), "the bold text survives")

    expectEqual(AnchoraPaperMap.pageIndexes(inText: blocks[0].text, pageLabels: labels).map(\.intValue), [3],
                "the citation still resolves after block splitting")
}

/// A pinned PDF note is plain text, so Markdown has to flatten legibly.
func testMarkdownPlainText() {
    let plain = AnchoraMarkdown.plainText(from: """
    ## Findings
    The **key** result is `n = 12`.

    - first
    - second
    > quoted
    """)
    expect(plain.contains("**") == false, "bold markers are gone from a pinned note")
    expect(plain.contains("`") == false, "backticks are gone from a pinned note")
    expect(plain.contains("##") == false, "heading markers are gone from a pinned note")
    expect(plain.contains("• first"), "bullets become readable markers")
    expect(plain.contains("The key result is n = 12."), "inline formatting flattens to its text")
    expect(plain.contains("“quoted”"), "a quote becomes quotation marks")
}

/// The formatting rules exist because the renderer cannot honour everything.
func testFormattingInstructionsMatchTheRenderer() {
    let instructions = AnchoraPrompts.systemInstructions(profile: .study, language: .english, webVerification: false)
    expect(instructions.contains("Markdown"), "answers are asked for in Markdown")
    expect(instructions.lowercased().contains("never use a markdown table"),
           "tables are ruled out, because the renderer has no table block")
    expect(instructions.contains("[PDF p. X]"), "the citation format is pinned so it stays literal")
}

// MARK: - Text quality

/// Slide decks often carry a text layer that is really a broken font mapping:
/// the characters live in a private use plane and come back as gibberish.
func testTextQualityHeuristic() {
    expect(AnchoraTextQuality.needsRecognition(rawText: "", cleanedText: "", textWithoutAliens: ""),
           "an empty selection always needs recognition")
    expect(AnchoraTextQuality.needsRecognition(rawText: "clean readable text",
                                               cleanedText: "clean readable text",
                                               textWithoutAliens: "clean readable text") == false,
           "an intact text layer is trusted")
    expect(AnchoraTextQuality.needsRecognition(rawText: "abcdefghij",
                                               cleanedText: "abcdefghi",
                                               textWithoutAliens: "abcdefghi") == false,
           "one unreadable character in ten is tolerated")
    expect(AnchoraTextQuality.needsRecognition(rawText: "abcdefghij",
                                               cleanedText: "abcdef",
                                               textWithoutAliens: "abcdef"),
           "losing a third or more of the selection means the layer is not trustworthy")
    expect(AnchoraTextQuality.needsRecognition(rawText: "abcdefghij",
                                               cleanedText: "",
                                               textWithoutAliens: "abcdefghi"),
           "cleaning down to nothing means recognition, however few aliens there were")
}

/// A Traditional Chinese slide recognised as nothing at all is what this list
/// exists to prevent.
func testRecognitionLanguageResolution() {
    let supported = ["en-US", "fr-FR", "zh-Hans", "zh-Hant", "ja-JP"]
    expectEqual(AnchoraTextQuality.resolveRecognitionLanguages(preferred: ["zh-Hant", "zh-Hans", "en-US"],
                                                              supported: supported),
                ["zh-Hant", "zh-Hans", "en-US"],
                "supported languages are kept in preference order")
    expectEqual(AnchoraTextQuality.resolveRecognitionLanguages(preferred: ["zh-Hant", "ko-KR", "en-US"],
                                                              supported: supported),
                ["zh-Hant", "en-US"],
                "an unsupported language is dropped, not fatal")
    expectEqual(AnchoraTextQuality.resolveRecognitionLanguages(preferred: ["ko-KR"], supported: supported),
                ["en-US"],
                "no preferred language available falls back rather than sending an empty list")
    expectEqual(AnchoraTextQuality.resolveRecognitionLanguages(preferred: ["zh-Hant"], supported: []),
                ["en-US"],
                "a machine that reports nothing falls back too")
}

/// Pin has to act on the answer it was shown under.  The reader often asks two
/// or three more questions before deciding an earlier answer was the useful one.
func testAnswersKeepTheirOwnTurn() {
    let model = AnchoraChatModel()
    let first = AnchoraTurn(question: "Explain this", conversationUserText: "Explain this",
                            selection: nil, hasTextSelection: false, page: nil, pageRect: .zero,
                            imageDataURL: nil, sourcePageIndexes: [NSNumber(value: 3)],
                            mapKind: .none, status: nil)
    let second = AnchoraTurn(question: "And this?", conversationUserText: "And this?",
                             selection: nil, hasTextSelection: false, page: nil, pageRect: .zero,
                             imageDataURL: nil, sourcePageIndexes: [NSNumber(value: 8)],
                             mapKind: .none, status: nil)

    model.beginStreamingMessage(status: "…", sourceLabel: "p. 3", sourcePageIndex: NSNumber(value: 2), turn: first)
    model.appendStreamedText("first answer")
    model.endStreaming()
    model.beginStreamingMessage(status: "…", sourceLabel: "p. 8", sourcePageIndex: NSNumber(value: 7), turn: second)
    model.appendStreamedText("second answer")
    model.endStreaming()

    expectEqual(model.messages.count, 2, "both answers are in the transcript")
    expectEqual(model.messages[0].turn?.question, "Explain this",
                "the first answer still carries the question it answered")
    expectEqual(model.messages[1].turn?.question, "And this?",
                "and the second carries its own")
    expectEqual(model.messages[0].turn?.sourcePageIndexes.map(\.intValue), [3],
                "an older answer keeps its own pin target after newer turns")
}

func testMessagesWithNothingToPin() {
    let model = AnchoraChatModel()
    model.appendUserMessage("a question")
    model.appendAssistantMessage("a hint with no turn behind it")
    expect(model.messages[0].turn == nil, "a user turn has nothing to pin")
    expect(model.messages[1].turn == nil, "a message that was not an answer has nothing to pin")
}

// MARK: - Inline markdown

private func spans(_ attributed: AttributedString, _ intent: InlinePresentationIntent) -> [String] {
    attributed.runs.compactMap { run in
        run.inlinePresentationIntent?.contains(intent) == true
            ? String(attributed[run.range].characters) : nil
    }
}

private func plain(_ attributed: AttributedString) -> String {
    String(attributed.characters)
}

/// CommonMark's flanking rules make emphasis unusable next to Chinese: the
/// closing run here is preceded by punctuation and followed by a Han
/// character, which disqualifies it, so the asterisks rendered literally.
func testEmphasisNextToChinese() {
    let attributed = AnchoraMarkdown.inline("**橫膈膜 (diaphragm)**收縮時向下變平")
    expectEqual(spans(attributed, .stronglyEmphasized), ["橫膈膜 (diaphragm)"],
                "bold closes even when punctuation precedes and a Han character follows")
    expectEqual(plain(attributed), "橫膈膜 (diaphragm)收縮時向下變平",
                "the asterisks are consumed rather than shown")

    let italic = AnchoraMarkdown.inline("這是*重點*，請記住")
    expectEqual(spans(italic, .emphasized), ["重點"], "italic closes before a full-width comma")
    expect(plain(italic).contains("*") == false, "no stray asterisk is left behind")
}

func testEmphasisOrdinaryCases() {
    expectEqual(spans(AnchoraMarkdown.inline("a **bold** b"), .stronglyEmphasized), ["bold"],
                "bold between spaces still works")
    expectEqual(spans(AnchoraMarkdown.inline("a *thin* b"), .emphasized), ["thin"],
                "single asterisks are emphasis")
    expectEqual(spans(AnchoraMarkdown.inline("a _thin_ b"), .emphasized), ["thin"],
                "underscores are emphasis too")
    expectEqual(plain(AnchoraMarkdown.inline("snake_case_name stays")), "snake_case_name stays",
                "underscores inside a word are not emphasis")
    expectEqual(plain(AnchoraMarkdown.inline("2 * 3 * 4")), "2 * 3 * 4",
                "asterisks with space after them are multiplication, not emphasis")
    expectEqual(plain(AnchoraMarkdown.inline(#"literal \*stars\* here"#)), "literal *stars* here",
                "a backslash escapes an asterisk")
}

/// Every flush re-parses a partial answer, so half-written syntax must degrade.
func testInlinePartialSyntax() {
    expectEqual(plain(AnchoraMarkdown.inline("this is **half a bold span")),
                "this is **half a bold span",
                "an unclosed run stays exactly as written")
    expectEqual(plain(AnchoraMarkdown.inline("an unclosed `code span")),
                "an unclosed `code span",
                "so does an unclosed code span")
    expectEqual(plain(AnchoraMarkdown.inline("")), "", "an empty block is empty")
}

func testInlineCodeAndLinks() {
    let code = AnchoraMarkdown.inline("set `n = 12` first")
    expectEqual(spans(code, .code), ["n = 12"], "backticks mark code")
    expectEqual(plain(code), "set n = 12 first", "the backticks themselves are consumed")

    let link = AnchoraMarkdown.inline("see [the paper](https://example.org/x) for detail")
    expectEqual(plain(link), "see the paper for detail", "link syntax is consumed")
    expect(link.runs.contains { $0.link?.absoluteString == "https://example.org/x" },
           "the destination becomes a real link")

    let bare = AnchoraMarkdown.inline("source: https://example.org/x")
    expect(bare.runs.contains { $0.link?.absoluteString == "https://example.org/x" },
           "a bare URL is still clickable")
}

/// The Paper Map resolves these afterwards, so they must survive as text.
func testCitationsAreNotLinks() {
    let attributed = AnchoraMarkdown.inline("**Direct evidence:** the assay failed [PDF p. 4]")
    expectEqual(spans(attributed, .stronglyEmphasized), ["Direct evidence:"], "the label is bold")
    expectEqual(plain(attributed), "Direct evidence: the assay failed [PDF p. 4]",
                "a bracket with no destination stays literal text")
    expect(attributed.runs.allSatisfy { $0.link == nil }, "and is not turned into a link")
}

func testNestedEmphasis() {
    let attributed = AnchoraMarkdown.inline("**bold with *inner* words**")
    expectEqual(plain(attributed), "bold with inner words", "both levels are consumed")
    expect(spans(attributed, .stronglyEmphasized).joined().contains("inner"),
           "the inner run is still bold")
    expect(spans(attributed, .emphasized) == ["inner"], "and additionally italic")
}

// MARK: - Header menu placement

/// SwiftUI reports frames from the top left. NSHostingView is flipped so that
/// matches directly, but an unflipped host needs the axis inverted -- getting
/// that backwards dropped the ••• menu below the CONTEXT card instead of below
/// the button.
func testMoreActionsMenuLocation() {
    let bounds = CGRect(x: 0, y: 0, width: 680, height: 146)
    let model = AnchoraHeaderModel()

    expectEqual(model.moreActionsMenuLocation(inViewBounds: bounds, isFlipped: true),
                CGPoint(x: 644, y: 0),
                "with nothing reported yet it falls back to the top right of a flipped view")
    expectEqual(model.moreActionsMenuLocation(inViewBounds: bounds, isFlipped: false),
                CGPoint(x: 644, y: 146),
                "and to the top right of an unflipped one, which is a different y")

    model.setMoreActionsAnchor(CGRect(x: 640, y: 0, width: 36, height: 20))
    expectEqual(model.moreActionsMenuLocation(inViewBounds: bounds, isFlipped: true),
                CGPoint(x: 640, y: 24),
                "a flipped host takes SwiftUI's frame directly, so the menu drops just below the button")
    expectEqual(model.moreActionsMenuLocation(inViewBounds: bounds, isFlipped: false),
                CGPoint(x: 640, y: 122),
                "an unflipped host measures the same point up from the bottom")

    let flipped = model.moreActionsMenuLocation(inViewBounds: bounds, isFlipped: true)
    expect(flipped.y < bounds.height * 0.5 && flipped.x > bounds.width * 0.5,
           "the menu lands in the top-right quadrant, where the button is")
}

// MARK: - Study map

/// A study plan has as many blocks as the material needs, with headings in
/// whatever language the reader chose, so it cannot be pinned to fixed
/// headings the way a paper map is.
func testStudyMapSplitsOnAnyHeading() {
    let response = """
    ## 1. 呼吸系統的整體架構
    Pages: [PDF p. 4-8]
    Goal: 說出氣流從鼻腔到肺泡的路徑

    ## 2. 胸廓與呼吸肌
    Pages: [PDF p. 19]
    Trap: 把桶柄效應和水泵柄效應搞混

    ### 3. 肋膜腔
    Pages: [PDF p. 13-14]

    ## 時間不夠時
    只讀 [PDF p. 19]
    """
    let sections = AnchoraStudyMap.sections(fromResponse: response, pageLabels: (1...30).map(String.init))
    expectEqual(sections.count, 4, "every heading becomes a block, however many there are")
    expectEqual(sections.map(\.title),
                ["1. 呼吸系統的整體架構", "2. 胸廓與呼吸肌", "3. 肋膜腔", "時間不夠時"],
                "headings keep their numbering, which is the reading order")
    expectEqual(sections[0].pageIndexes.map(\.intValue), [3, 4, 5, 6, 7],
                "a page range in a block resolves to its pages")
    expectEqual(sections[3].pageIndexes.map(\.intValue), [18],
                "so does the short path at the end")
    expect(sections[1].text.contains("Trap:"), "a block keeps its own body")
}

func testStudyMapTitleIsPlainText() {
    let sections = AnchoraStudyMap.sections(fromResponse: "## **1. Gas exchange**\nbody", pageLabels: ["1"])
    expectEqual(sections.map(\.title), ["1. Gas exchange"],
                "a decorated heading is shown as plain text in the picker")
}

func testStudyMapWithoutHeadings() {
    let sections = AnchoraStudyMap.sections(fromResponse: "read it front to back [PDF p. 2]", pageLabels: ["1", "2"])
    expectEqual(sections.count, 1, "a plan with no headings is still shown")
    expectEqual(sections[0].pageIndexes.map(\.intValue), [1], "and still resolves its citations")
    expectEqual(AnchoraStudyMap.sections(fromResponse: "", pageLabels: ["1"]).count, 0,
                "an empty response yields nothing")
}

/// The row is the reading loop; everything else is one level down in the
/// ••• menu.  What matters is that the split loses nothing: an action that is
/// in neither list cannot be reached at all.
func testEveryActionIsReachableExactlyOnce() {
    for profile in [AnchoraReadingProfile.study, .scientific] {
        let row = (0..<AnchoraPrompts.quickActionTitles(profile: profile).count)
            .map { AnchoraPrompts.rowAction(profile: profile, index: $0) }
        let overflow = AnchoraPrompts.overflowActions(profile: profile)
            .map { AnchoraQuickAction(rawValue: $0.intValue)! }
        expectEqual(row.count, 3, "the row is three buttons")
        expectEqual(AnchoraPrompts.quickActionTooltips(profile: profile).count, row.count,
                    "every button explains itself")
        let offered = row + overflow
        expectEqual(Set(offered.map(\.rawValue)).count, offered.count,
                    "no action is offered in both places")
        for action in offered {
            expect(AnchoraPrompts.title(for: action).isEmpty == false, "every action has a button label")
            expect(AnchoraPrompts.menuTitle(for: action).isEmpty == false, "and a menu title")
            expect(AnchoraPrompts.displayTitle(for: action).isEmpty == false, "and a title for the transcript")
            expect(AnchoraPrompts.tooltip(for: action).isEmpty == false, "and a tooltip")
        }
    }

    let study = (0..<3).map { AnchoraPrompts.rowAction(profile: .study, index: $0) }
    expectEqual(study, [.explain, .recall, .quiz], "the study row is the reading loop, in the order it is used")
    expectEqual(AnchoraPrompts.overflowActions(profile: .study).map(\.intValue),
                [AnchoraQuickAction.studyMap, .translate, .clinical].map(\.rawValue),
                "the study map and the occasional lenses moved into •••")
    expectEqual((0..<3).map { AnchoraPrompts.rowAction(profile: .scientific, index: $0) },
                [.methods, .figure, .evidence], "the scientific row keeps the three per-selection lenses")

    // The paper map is absent from the overflow on purpose: ••• already
    // builds it as this profile's whole-PDF summary.
    expect(AnchoraPrompts.overflowActions(profile: .scientific)
        .contains(NSNumber(value: AnchoraQuickAction.paperMap.rawValue)) == false,
           "the paper map is not listed twice in the same menu")
    expectEqual(AnchoraPrompts.documentSummaryPrompt(profile: .scientific),
                AnchoraPrompts.prompt(for: .paperMap), "because the whole-PDF summary is that prompt")

    // A row index that no longer exists must not crash or silently fire
    // whatever action happens to sit at that raw value.
    expectEqual(AnchoraPrompts.rowAction(profile: .study, index: 9), .explain, "an out-of-range button is inert")
    expectEqual(AnchoraPrompts.rowAction(profile: .study, index: -1), .explain, "in both directions")
}

/// What an action needs in front of it is a property of the action, not of
/// which button happens to be pressed.
func testActionScopes() {
    expectEqual(AnchoraPrompts.scope(for: .recall), .page, "recall is asked about the page just read")
    expectEqual(AnchoraPrompts.scope(for: .quiz), .page, "so is the quiz")
    expectEqual(AnchoraPrompts.scope(for: .studyMap), .document, "a study map plans the whole document")
    expectEqual(AnchoraPrompts.scope(for: .paperMap), .document, "and a paper map rebuilds the whole paper")
    for action in [AnchoraQuickAction.explain, .translate, .clinical, .methods, .figure, .evidence] {
        expectEqual(AnchoraPrompts.scope(for: action), .selection, "\(action) acts on what is selected")
    }

    expectEqual(AnchoraPrompts.mapKind(for: .studyMap), .study, "each map lands in its own navigator")
    expectEqual(AnchoraPrompts.mapKind(for: .paperMap), .paper, "both of them")
    expectEqual(AnchoraPrompts.mapKind(for: .explain), AnchoraMapKind.none, "an ordinary answer is not a map")

    expectEqual(AnchoraPrompts.prompt(for: .studyMap), AnchoraPrompts.studyMapPrompt, "Study map kept its prompt")
    expect(AnchoraPrompts.prompt(for: .explain).contains("step by step"), "so did Explain")
    expect(AnchoraPrompts.prompt(for: .translate).contains("Translate"), "and Translate")
    expect(AnchoraPrompts.prompt(for: .clinical).contains("clinical"), "and Clinical")
    expect(AnchoraPrompts.prompt(for: .methods).contains("controls"), "and Methods")
    // Recall has nothing to ask until the reader has written something.
    expectEqual(AnchoraPrompts.prompt(for: .recall), "", "recall carries no standalone prompt")
}

/// A quiz that answers itself, or that asks which slide something was on,
/// produces a feedback signal that is not about understanding.
func testQuizAsksRatherThanTells() {
    let prompt = AnchoraPrompts.quizPrompt
    expect(prompt.contains("Do not answer them"), "the questions arrive without their answers")
    expect(prompt.contains("do not hint"), "and without hints")
    expect(prompt.lowercased().contains("not whether i can remember how it was worded"),
           "it tests use, not recognition of the wording")
    expect(prompt.contains("copied off the page"), "an answer that can be copied off the page is not a question")
    expect(prompt.lowercased().contains("which slide"), "and neither is where something appeared")
    expect(prompt.lowercased().contains("ask bar"), "the reader is told where the answers go")

    let grading = AnchoraPrompts.quizGradingPrompt(answers: "1. because the pressure drops")
    expect(grading.contains("1. because the pressure drops"), "the marking carries what was answered")
    expect(grading.contains("softened version") , "and is not allowed to soften what is wrong")
    expect(grading.lowercased().contains("fewer questions"), "an incomplete answer is still marked")
    expectEqual(AnchoraPrompts.quizDisplayTitle(pageNumber: 7), "Quiz me on page 7",
                "the transcript names the page that was quizzed")
}

/// Recall is a diff, not a summary: if the model summarises the page, the
/// reader learns nothing about what they actually failed to encode.
func testRecallComparesRatherThanSummarises() {
    let prompt = AnchoraPrompts.recallPrompt(summary: "the alveoli swap gas by active transport")
    expect(prompt.contains("the alveoli swap gas by active transport"), "the reader's own sentence is what gets marked")
    expect(prompt.contains("Do not summarise the page"), "it is a comparison, not a summary")
    expect(prompt.contains("**Wrong**") && prompt.contains("**Missed**"),
           "wrong and missing are reported separately -- they call for different fixes")
    expect(prompt.contains("Judge the idea, not the wording"), "loose phrasing of a correct idea is correct")
    expect(prompt.contains("do not soften"), "and being told plainly is the point")
    expect(AnchoraPrompts.recallNeedsSummaryMessage.contains("from memory"),
           "an empty ask bar is told why writing first matters")
}

/// It plans how to study the document; it does not summarise it.
func testStudyMapPromptAsksForAPlan() {
    let prompt = AnchoraPrompts.studyMapPrompt
    expect(prompt.contains("not a summary"), "the plan is explicitly not a summary")
    expect(prompt.contains("[PDF p. X]"), "pages are cited in the form the navigator resolves")
    expect(prompt.contains("H2"), "blocks are headings, which is what the parser splits on")
    expect(prompt.lowercased().contains("depends on"), "the order is by dependency, not page order")
    expect(prompt.lowercased().contains("short of time"), "there is a short path for a reader in a hurry")
}

// MARK: - The store

/// Every store test gets its own directory: the point of the store is what
/// survives, so a test that read another test's leftovers would prove nothing.
func makeStore(_ label: String) -> AnchoraStore {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("anchora-tests-\(label)-\(UUID().uuidString)")
    return AnchoraStore(directory: directory)
}

/// A store that has never been written to is the normal first-run state, not
/// an error, and a note has to survive being written and read back.
func testInboxRoundTrip() {
    let store = makeStore("inbox")
    expectEqual(store.notes().count, 0, "a store with no file behind it is empty, not broken")
    expectEqual(store.openNoteCount(), 0, "and nothing is waiting")

    store.addNote(text: "look up the half-life", sourceTitle: "Pharmacokinetics", sourcePage: 14)
    store.addNote(text: "reply to Ben", sourceTitle: nil, sourcePage: 0)
    let notes = store.notes()
    expectEqual(notes.count, 2, "both notes were kept")
    expectEqual(notes.first?.text, "reply to Ben", "newest first: the thought just written is the live one")
    expectEqual(notes.last?.sourcePage, 14, "and a note remembers the page it was written on")

    expect(store.addNote(text: "   ", sourceTitle: nil, sourcePage: 0) == nil,
           "an accidental Return leaves nothing to tidy up")
    expectEqual(store.notes().count, 2, "and stores nothing")

    let store2 = AnchoraStore(directory: URL(fileURLWithPath: "/nonexistent-anchora-\(UUID().uuidString)"))
    expectEqual(store2.notes().count, 0, "an unreadable store reads as empty rather than throwing")
}

/// Completing something is not deleting it; clearing is.
func testInboxCompletionAndDeletion() {
    let store = makeStore("done")
    store.addNote(text: "one", sourceTitle: nil, sourcePage: 0)
    store.addNote(text: "two", sourceTitle: nil, sourcePage: 0)
    guard let first = store.notes().first else { return expect(false, "a note was stored") }

    store.setNote(id: first.id, done: true)
    expectEqual(store.openNoteCount(), 1, "a completed note stops being outstanding")
    expectEqual(store.notes().count, 2, "but it is still there")
    store.setNote(id: first.id, done: false)
    expectEqual(store.openNoteCount(), 2, "and can be put back on the list")

    store.setNote(id: "a note that does not exist", done: true)
    expectEqual(store.openNoteCount(), 2, "an unknown id changes nothing")

    store.setNote(id: first.id, done: true)
    store.deleteDoneNotes()
    expectEqual(store.notes().count, 1, "clearing takes only what was finished")
    expectEqual(store.openNoteCount(), 1, "and leaves what is still open")

    guard let survivor = store.notes().first else { return expect(false, "one note survived") }
    store.deleteNote(id: survivor.id)
    expectEqual(store.notes().count, 0, "deleting takes the note itself")
}

/// A note is worth little a day later without where it was written.
func testNoteSourceDescription() {
    expectEqual(AnchoraNote(text: "x", sourceTitle: "Gas exchange", sourcePage: 9).sourceDescription,
                "p. 9 · Gas exchange", "page and document, when both are known")
    expectEqual(AnchoraNote(text: "x", sourceTitle: "Gas exchange", sourcePage: 0).sourceDescription,
                "Gas exchange", "just the document when there is no page")
    expect(AnchoraNote(text: "x", sourceTitle: nil, sourcePage: 3).sourceDescription == nil,
           "and nothing at all when it was not written while reading")
}

/// A map costs a whole-PDF upload. Reopening the document must not ask for it
/// again.
func testMapsAreKeptPerDocument() {
    let store = makeStore("maps")
    let lecture = "/Users/someone/Lectures/respiration.pdf"
    let paper = "/Users/someone/Papers/hypoxia.pdf"

    expect(store.latestMap(documentPath: lecture) == nil, "a document with no map has none")
    expect(store.latestMap(documentPath: "") == nil, "and an unsaved document cannot have one")

    store.saveMap(response: "## Gas exchange", kindRawValue: AnchoraMapKind.study.rawValue,
                  documentPath: lecture, title: "respiration.pdf")
    store.saveMap(response: "## Objective", kindRawValue: AnchoraMapKind.paper.rawValue,
                  documentPath: paper, title: "hypoxia.pdf")

    expectEqual(store.latestMap(documentPath: lecture)?.response, "## Gas exchange",
                "the lecture's map comes back")
    expectEqual(store.latestMap(documentPath: lecture)?.kindRawValue, AnchoraMapKind.study.rawValue,
                "as the kind it was built as")
    expectEqual(store.latestMap(documentPath: paper)?.response, "## Objective",
                "and each document keeps its own")

    // Rebuilding replaces rather than accumulates.
    store.saveMap(response: "## Gas exchange, again", kindRawValue: AnchoraMapKind.study.rawValue,
                  documentPath: lecture, title: "respiration.pdf")
    expectEqual(store.map(kindRawValue: AnchoraMapKind.study.rawValue, documentPath: lecture)?.response,
                "## Gas exchange, again", "a rebuilt map replaces the one before it")

    store.saveMap(response: "", kindRawValue: AnchoraMapKind.study.rawValue,
                  documentPath: lecture, title: "respiration.pdf")
    expectEqual(store.latestMap(documentPath: lecture)?.response, "## Gas exchange, again",
                "an empty response never overwrites a real map")

    store.deleteMaps(documentPath: lecture)
    expect(store.latestMap(documentPath: lecture) == nil, "deleting takes that document's maps")
    expect(store.latestMap(documentPath: paper) != nil, "and leaves every other document alone")
}

/// Both kinds can exist for one document; the one restored on open is the one
/// most recently built.
func testLatestMapWins() {
    let store = makeStore("latest")
    let path = "/Users/someone/both.pdf"
    store.saveMap(response: "paper", kindRawValue: AnchoraMapKind.paper.rawValue,
                  documentPath: path, title: "both.pdf")
    // Saved dates come from the clock, so make the second one unambiguously later.
    Thread.sleep(forTimeInterval: 1.1)
    store.saveMap(response: "study", kindRawValue: AnchoraMapKind.study.rawValue,
                  documentPath: path, title: "both.pdf")
    expectEqual(store.latestMap(documentPath: path)?.response, "study",
                "the map built most recently is the one waiting behind the tab")
    expectEqual(store.map(kindRawValue: AnchoraMapKind.paper.rawValue, documentPath: path)?.response, "paper",
                "and the other is still addressable by kind")
}

/// The key is a digest of the path, so two documents cannot share a file and
/// one document keeps the same file across launches.
func testDocumentKeys() {
    let a = AnchoraStore.documentKey(forPath: "/a/b.pdf")
    expectEqual(a, AnchoraStore.documentKey(forPath: "/a/b.pdf"), "the same path keys the same record")
    expect(a != AnchoraStore.documentKey(forPath: "/a/c.pdf"), "different documents do not collide")
    expectEqual(a.count, 64, "a SHA-256 digest, so it is a legal filename of known length")
}

/// The inbox drawer and the Command-Shift-J panel are two views of one list.
func testInboxModelWritesThrough() {
    let store = makeStore("model")
    let model = AnchoraInboxModel(store: store)
    model.sourceTitleProvider = { "Respiration" }
    model.sourcePageProvider = { 22 }

    model.draft = "check the shunt equation"
    expect(model.addDraft(), "a draft with something in it is stored")
    expectEqual(model.draft, "", "and the field is emptied, ready for the next one")
    expectEqual(model.openCount, 1, "the badge counts it")
    expectEqual(model.notes.first?.sourcePage, 22, "the source is asked for at the moment of writing")

    model.draft = "  "
    expect(model.addDraft() == false, "an empty draft is not a note")
    expectEqual(model.openCount, 1, "and does not move the count")

    // A second view of the same store sees it, which is what the panel needs.
    let other = AnchoraInboxModel(store: store)
    expectEqual(other.openCount, 1, "another view of the same inbox sees the same list")

    guard let note = model.notes.first else { return expect(false, "the note is there") }
    model.setDone(note, true)
    expectEqual(model.openCount, 0, "completing it clears the badge")
    other.reload()
    expectEqual(other.openCount, 0, "in every view of it")
    expectEqual(model.doneNotes.count, 1, "while the note itself is kept")
}

/// A tab whose content has gone must not stay selected.
func testPaneTabFallback() {
    let pane = AnchoraPaneModel()
    expectEqual(pane.tab, .chat, "the sidebar opens on the conversation")
    pane.showMap()
    expectEqual(pane.tab, .map, "and switches when a map is built")
    pane.leaveTabIfShowing(.inbox)
    expectEqual(pane.tab, .map, "leaving a tab it is not on changes nothing")
    pane.leaveTabIfShowing(.map)
    expectEqual(pane.tab, .chat, "a cleared map hands the area back to the conversation")
}

// MARK: - The composer's height, and the context line

/// The composer is still given an explicit height by AppKit; what changed is
/// that the number moves.  The clamp is what keeps a growing field from eating
/// the sidebar, so it is the part worth pinning down.
func testComposerHeightClamp() {
    expectEqual(AnchoraComposerModel.clampHeight(10.0), AnchoraComposerModel.minimumHeight,
                "the composer never goes below one line plus its two rows")
    expectEqual(AnchoraComposerModel.clampHeight(10_000.0), AnchoraComposerModel.maximumHeight,
                "and never grows without limit -- past the cap the field scrolls")
    expectEqual(AnchoraComposerModel.clampHeight(120.0), 120.0, "anything in between is used as measured")
    expectEqual(AnchoraComposerModel.clampHeight(.nan), AnchoraComposerModel.minimumHeight,
                "a measurement that is not a number is not allowed into a constraint")
    expectEqual(AnchoraComposerModel.clampHeight(.infinity), AnchoraComposerModel.minimumHeight,
                "nor an infinite one")
    expect(AnchoraComposerModel.minimumHeight < AnchoraComposerModel.maximumHeight,
           "the two bounds are the right way round")

    expectEqual(AnchoraComposerModel.clampFieldHeight(1.0), AnchoraComposerModel.minimumFieldHeight,
                "the text itself starts at one line")
    expectEqual(AnchoraComposerModel.clampFieldHeight(10_000.0), AnchoraComposerModel.maximumFieldHeight,
                "and stops at about six")
}

/// Sending empties the field, and the composer has to come back down with it:
/// there is no keystroke to report a height when the text is removed from
/// under it.
func testClearingTheQuestionShrinksTheField() {
    let model = AnchoraComposerModel()
    model.reportFieldHeight(90.0)
    expectEqual(model.fieldHeight, 90.0, "a measured height is taken")
    model.setQuestionText("")
    expectEqual(model.fieldHeight, AnchoraComposerModel.minimumFieldHeight,
                "and an emptied field returns to one line")

    model.reportFieldHeight(90.0)
    model.setQuestionText("still something here")
    expectEqual(model.fieldHeight, 90.0, "while replacing the text leaves the measured height alone")
}

/// The context card became one line, so what goes on that line has to survive
/// the hard line breaks a PDF text layer is full of -- they mean nothing
/// outside the page's own column width, and truncating at the first one would
/// show almost nothing.
func testContextSummaryIsOneLine() {
    expectEqual(AnchoraHeaderModel.summary(of: "alveolar\nventilation\nand perfusion"),
                "alveolar ventilation and perfusion", "line breaks in the text layer are collapsed")
    expectEqual(AnchoraHeaderModel.summary(of: "  spaced   out  "), "spaced   out",
                "the ends are trimmed without rewriting the middle")
    expectEqual(AnchoraHeaderModel.summary(of: "\n\n"), "", "text that is only breaks summarises to nothing")

    let model = AnchoraHeaderModel()
    model.setContextText("Select text in the PDF to give AI context.", expandable: false)
    expect(model.isContextExpandable == false, "a message about what to do has nothing more to show")
    model.setContextText("The alveolar gas equation is", expandable: true)
    expect(model.isContextExpandable, "extracted text does -- it is what will actually be sent")
    model.setContextText("   ", expandable: true)
    expect(model.isContextExpandable == false, "but there is nothing to open when there is no text")
}

// MARK: - Photographs from an iPhone

/// A phone hands over a twelve-megapixel photograph of a handout. Sending that
/// as it arrives is slow and expensive and reads no better, so it is scaled
/// down -- but never up, because enlarging a small photo only costs money.
func testPhotoScaling() {
    expectEqual(AnchoraCapture.photoScale(width: 4032.0, height: 3024.0), 2048.0 / 4032.0,
                "a large photo is scaled by its longest side")
    expectEqual(AnchoraCapture.photoScale(width: 3024.0, height: 4032.0), 2048.0 / 4032.0,
                "portrait or landscape makes no difference")
    expectEqual(AnchoraCapture.photoScale(width: 800.0, height: 600.0), 1.0,
                "a photo already smaller than the ceiling is left alone")
    expectEqual(AnchoraCapture.photoScale(width: 2048.0, height: 1000.0), 1.0,
                "and one exactly at it is not touched either")
    expectEqual(AnchoraCapture.photoScale(width: 0.0, height: 0.0), 1.0,
                "an empty image does not divide by zero")
}

/// End to end on the image itself: what goes to the model is a JPEG data URL
/// at a sane size, whatever the phone produced.
///
/// The fixtures are built from an explicit bitmap rather than by drawing into
/// an NSImage, because lockFocus allocates a backing store at the screen's
/// scale -- a "300 point" image is 600 pixels on this display, and the scaling
/// here is rightly about pixels.
func makePhoto(pixelsWide: Int, pixelsHigh: Int) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
    NSColor.black.setFill()
    NSRect(x: 10, y: 10, width: pixelsWide / 3, height: pixelsHigh / 3).fill()
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
    image.addRepresentation(rep)
    return image
}

func decodePhoto(_ url: String?) -> NSBitmapImageRep? {
    let prefix = "data:image/jpeg;base64,"
    guard let url, url.hasPrefix(prefix),
          let data = Data(base64Encoded: String(url.dropFirst(prefix.count)))
    else { return nil }
    return NSBitmapImageRep(data: data)
}

func testDownscaledPhoto() {
    let large = AnchoraCapture.downscaledPhoto(from: makePhoto(pixelsWide: 4032, pixelsHigh: 3024))
    guard let rep = large?.representations.first else {
        return expect(false, "a photograph comes back as an image")
    }
    expectEqual(rep.pixelsWide, 2048, "scaled to the ceiling on its longest side")
    expectEqual(rep.pixelsHigh, 1536, "keeping its aspect ratio")

    guard let small = AnchoraCapture.downscaledPhoto(from: makePhoto(pixelsWide: 300, pixelsHigh: 200))?
        .representations.first
    else { return expect(false, "a small photograph still works") }
    expectEqual(small.pixelsWide, 300, "and is passed through at its own size rather than enlarged")

    guard let portrait = AnchoraCapture.downscaledPhoto(from: makePhoto(pixelsWide: 3024, pixelsHigh: 4032))?
        .representations.first
    else { return expect(false, "a portrait photograph works") }
    expectEqual(portrait.pixelsHigh, 2048, "the longest side is the one that meets the ceiling")

    expect(AnchoraCapture.downscaledPhoto(from: NSImage(size: .zero)) == nil,
           "an empty image produces nothing rather than an empty note")
}

/// Where a photograph lands when it is dropped into a page.  It annotates the
/// page; it must not take it over, and it must not arrive distorted.
func testPhotoNoteBounds() {
    let page = NSRect(x: 0.0, y: 0.0, width: 600.0, height: 800.0)

    let landscape = AnchoraCapture.photoNoteBounds(imageSize: NSSize(width: 4000.0, height: 3000.0),
                                                   pageBounds: page)
    expectEqual(landscape.width, 300.0, "a wide photo is held to half the page's width")
    expectEqual(landscape.height, 225.0, "and keeps its aspect ratio")
    expectEqual(landscape.midX, page.midX, "centred across the page")
    expectEqual(landscape.midY, page.midY, "and down it")

    let tall = AnchoraCapture.photoNoteBounds(imageSize: NSSize(width: 1000.0, height: 4000.0),
                                              pageBounds: page)
    expectEqual(tall.height, 400.0, "a tall photo is held to half the page's height instead")
    expectEqual(tall.width, 100.0, "still in proportion")
    expect(tall.maxY <= page.maxY && tall.minY >= page.minY, "and stays on the page")

    // A page-shaped photo must be limited by both, not by whichever is checked
    // first.
    let matching = AnchoraCapture.photoNoteBounds(imageSize: NSSize(width: 600.0, height: 800.0),
                                                  pageBounds: page)
    expect(matching.width <= page.width / 2.0 && matching.height <= page.height / 2.0,
           "neither dimension runs past half the page")

    expectEqual(AnchoraCapture.photoNoteBounds(imageSize: .zero, pageBounds: page), .zero,
                "an empty image has no bounds to occupy")
    expectEqual(AnchoraCapture.photoNoteBounds(imageSize: NSSize(width: 10.0, height: 10.0),
                                               pageBounds: .zero), .zero,
                "and neither does a page with no size")
}

// MARK: - Capture geometry

/// Two things have to be undone before a page rectangle matches what drawing
/// produces: the display box origin, and the page rotation.  A deck stored as
/// portrait pages rotated 90 degrees reports an unrotated, portrait rectangle
/// for a drag the reader made on a landscape slide.
func testRenderRectUnrotatedPage() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    expectEqual(AnchoraCapture.renderRect(for: CGRect(x: 30, y: 390, width: 540, height: 70),
                                          pageBounds: bounds, rotation: 0),
                CGRect(x: 30, y: 390, width: 540, height: 70),
                "an unrotated page at the origin needs no mapping")
}

func testRenderRectSubtractsTheBoxOrigin() {
    let offset = CGRect(x: 50, y: 30, width: 600, height: 800)
    expectEqual(AnchoraCapture.renderRect(for: CGRect(x: 85, y: 425, width: 530, height: 70),
                                          pageBounds: offset, rotation: 0),
                CGRect(x: 35, y: 395, width: 530, height: 70),
                "an offset box origin is subtracted")
    expectEqual(AnchoraCapture.renderRect(for: offset, pageBounds: offset, rotation: 0),
                CGRect(x: 0, y: 0, width: 600, height: 800),
                "capturing the whole page starts at the context origin")
}

func testRenderRectRotations() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    // A band across the middle of the unrotated page, deliberately asymmetric
    // in x so a rotation and a mere transpose give different answers.
    let band = CGRect(x: 25, y: 595, width: 210, height: 60)

    expectEqual(AnchoraCapture.renderRect(for: band, pageBounds: bounds, rotation: 90),
                CGRect(x: 595, y: 365, width: 60, height: 210),
                "90 degrees maps x from y and y from the far edge of x")
    expectEqual(AnchoraCapture.renderRect(for: band, pageBounds: bounds, rotation: 180),
                CGRect(x: 365, y: 145, width: 210, height: 60),
                "180 degrees mirrors both axes and keeps the shape")
    expectEqual(AnchoraCapture.renderRect(for: band, pageBounds: bounds, rotation: 270),
                CGRect(x: 145, y: 25, width: 60, height: 210),
                "270 degrees is the opposite quarter turn")

    expectEqual(AnchoraCapture.renderRect(for: band, pageBounds: bounds, rotation: 450),
                AnchoraCapture.renderRect(for: band, pageBounds: bounds, rotation: 90),
                "a rotation beyond a full turn is normalised")
    expectEqual(AnchoraCapture.renderRect(for: band, pageBounds: bounds, rotation: -90),
                AnchoraCapture.renderRect(for: band, pageBounds: bounds, rotation: 270),
                "a negative rotation is normalised")
}

/// A quarter-turned page draws into a canvas whose sides are swapped, so a
/// whole-page capture has to swap them too.
func testRenderRectWholePageOnARotatedPage() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    expectEqual(AnchoraCapture.renderRect(for: bounds, pageBounds: bounds, rotation: 90),
                CGRect(x: 0, y: 0, width: 800, height: 600),
                "the whole page fills a landscape canvas when the page is quarter-turned")
    expectEqual(AnchoraCapture.renderRect(for: bounds, pageBounds: bounds, rotation: 180),
                CGRect(x: 0, y: 0, width: 600, height: 800),
                "a half turn keeps the canvas shape")
}

// MARK: - Selection and turn

func testSelectionGenerationAdvances() {
    let first = AnchoraSelection.empty(message: "nothing", after: nil)
    let second = AnchoraSelection.recognizing(selection: nil, hasTextSelection: false, page: nil, pageRect: .zero,
                                              message: "reading…", after: first)
    let third = AnchoraSelection.empty(message: "nothing", after: second)
    expect(second.generation > first.generation, "a new selection advances the generation")
    expect(third.generation > second.generation, "and keeps advancing")
}

/// Recognition runs off the main thread; its result must still belong to the
/// selection the reader made, so finishing keeps the generation it started with.
func testFinishingRecognitionKeepsItsGeneration() {
    let pending = AnchoraSelection.recognizing(selection: nil, hasTextSelection: false, page: nil, pageRect: .zero,
                                               message: "reading…", after: nil)
    let finished = pending.byFinishingRecognition(text: "  recovered text  ", failureMessage: "failed")
    expectEqual(finished.generation, pending.generation, "finishing recognition does not advance the generation")
    expectEqual(finished.text, "recovered text", "recognised text is trimmed")
    expectEqual(finished.contextDescription, "recovered text", "the context card shows what was recovered")
    expect(finished.isRecognizingText == false, "recognition is no longer in progress")
    expect(finished.hasContext, "recovered text counts as context")
}

func testFinishingRecognitionWithNothing() {
    let pending = AnchoraSelection.recognizing(selection: nil, hasTextSelection: false, page: nil, pageRect: .zero,
                                               message: "reading…", after: nil)
    for empty in [nil, "", "   \n  "] {
        let finished = pending.byFinishingRecognition(text: empty, failureMessage: "failed")
        expect(finished.text == nil, "whitespace-only recognition yields no context")
        expectEqual(finished.contextDescription, "failed", "the reader is told recognition failed")
        expect(finished.hasContext == false, "a failed recognition is not sendable context")
    }
}

func testSelectionContextStates() {
    let empty = AnchoraSelection.empty(message: "Select text in the PDF to give AI context.", after: nil)
    expect(empty.hasContext == false, "an empty selection has no context")
    expect(empty.isRecognizingText == false, "an empty selection is not recognising")

    let recognising = AnchoraSelection.recognizing(selection: nil, hasTextSelection: false, page: nil, pageRect: .zero,
                                                   message: "reading…", after: empty)
    expect(recognising.hasContext == false, "a selection mid-recognition has nothing to send yet")
    expect(recognising.isRecognizingText, "a selection mid-recognition says so")
}

func testTurnCannotPinWithoutAnAnchorOrAnAnswer() {
    let turn = AnchoraTurn(question: "Explain this", conversationUserText: "Explain this",
                           selection: nil, hasTextSelection: false, page: nil, pageRect: .zero, imageDataURL: nil,
                           sourcePageIndexes: [], mapKind: .none, status: "Waiting…")
    expect(turn.canPin == false, "a turn with no answer cannot be pinned")
    turn.receivedOutput = true
    expect(turn.canPin == false, "an answer with nowhere in the PDF to anchor it cannot be pinned")
}

/// A follow-up question carries no selection of its own, so the page the
/// reader is on is handed in as the anchor.  Without it every answer after
/// the first in a conversation was unpinnable, which is what the sidebar was
/// actually doing.
func testAnAnswerAnchoredToAPageCanBePinned() {
    let page = PDFPage()
    let turn = AnchoraTurn(question: "And why is that?", conversationUserText: "And why is that?",
                           selection: nil, hasTextSelection: false, page: page,
                           pageRect: CGRect(x: 0, y: 0, width: 600, height: 800), imageDataURL: nil,
                           sourcePageIndexes: [], mapKind: .none, status: nil)
    expect(turn.canPin == false, "still not while the answer is on its way")
    turn.receivedOutput = true
    expect(turn.canPin, "an answered follow-up anchors to the page it was asked on")
    expect(turn.page === page, "and keeps that page")

    // A text selection anchors to itself; the page passed alongside it is
    // deliberately dropped, so handing one in cannot produce a turn anchored
    // to both.
    let selected = AnchoraTurn(question: "Explain this", conversationUserText: "Explain this",
                               selection: nil, hasTextSelection: true, page: page,
                               pageRect: CGRect(x: 0, y: 0, width: 600, height: 800), imageDataURL: nil,
                               sourcePageIndexes: [], mapKind: .none, status: nil)
    expect(selected.page == nil, "a turn anchored to a selection is not also anchored to a page")
    selected.receivedOutput = true
    expect(selected.canPin, "and is still pinnable")
}

func testTurnAccumulatesItsAnswer() {
    let turn = AnchoraTurn(question: "Explain this", conversationUserText: "Explain this",
                           selection: nil, hasTextSelection: false, page: nil, pageRect: .zero, imageDataURL: nil,
                           sourcePageIndexes: [NSNumber(value: 3)], mapKind: .paper, status: nil)
    turn.response.append("first ")
    turn.response.append("second")
    expectEqual(turn.response as String, "first second", "streamed deltas accumulate on the turn")
    expectEqual(turn.sourcePageIndexes.map(\.intValue), [3], "the turn keeps the pages it was asked about")
    expect(turn.isMap && turn.mapKind == .paper, "the turn remembers which navigator its answer belongs in")
}

// MARK: - Run

// A multi-file swiftc invocation has no main.swift, so the entry point is
// explicit rather than top-level code.
@main
enum AnchoraCoreTests {
    static func main() {
        testAllHeadingsSplit()
        testLimitationsHeadingVariants()
        testUnstructuredResponseStillYieldsOneSection()
        testEmptySectionGetsPlaceholder()
        testCitationResolution()
        testCitationResolvesNonNumericLabels()
        testPromptHeadingsAreParseable()
        testSettings()
        testPromptsFollowSettings()
        testChatStreamingLifecycle()
        testChatStopAndError()
        testChatPaperMapRemovesItsBubble()
        testChatSurvivesClearMidStream()
        testChatHintDeduplication()
        testChatSenderNames()
        testAnswersKeepTheirOwnTurn()
        testMessagesWithNothingToPin()
        testMoreActionsMenuLocation()
        testStudyMapSplitsOnAnyHeading()
        testStudyMapTitleIsPlainText()
        testStudyMapWithoutHeadings()
        testEveryActionIsReachableExactlyOnce()
        testActionScopes()
        testQuizAsksRatherThanTells()
        testRecallComparesRatherThanSummarises()
        testInboxRoundTrip()
        testInboxCompletionAndDeletion()
        testNoteSourceDescription()
        testMapsAreKeptPerDocument()
        testLatestMapWins()
        testDocumentKeys()
        testInboxModelWritesThrough()
        testPaneTabFallback()
        testComposerHeightClamp()
        testClearingTheQuestionShrinksTheField()
        testContextSummaryIsOneLine()
        testStudyMapPromptAsksForAPlan()
        testMarkdownBlockKinds()
        testMarkdownNestedList()
        testMarkdownHandlesPartialStreamedText()
        testMarkdownBlockIdentityIsStable()
        testMarkdownPreservesCitations()
        testMarkdownPlainText()
        testFormattingInstructionsMatchTheRenderer()
        testEmphasisNextToChinese()
        testEmphasisOrdinaryCases()
        testInlinePartialSyntax()
        testInlineCodeAndLinks()
        testCitationsAreNotLinks()
        testNestedEmphasis()
        testTextQualityHeuristic()
        testRecognitionLanguageResolution()
        testPhotoScaling()
        testDownscaledPhoto()
        testPhotoNoteBounds()
        testRenderRectUnrotatedPage()
        testRenderRectSubtractsTheBoxOrigin()
        testRenderRectRotations()
        testRenderRectWholePageOnARotatedPage()
        testSelectionGenerationAdvances()
        testFinishingRecognitionKeepsItsGeneration()
        testFinishingRecognitionWithNothing()
        testSelectionContextStates()
        testTurnCannotPinWithoutAnAnchorOrAnAnswer()
        testAnAnswerAnchoredToAPageCanBePinned()
        testTurnAccumulatesItsAnswer()

        if failures == 0 {
            print("AnchoraCoreTests: \(checks) checks passed")
        } else {
            print("AnchoraCoreTests: \(failures) of \(checks) checks FAILED")
            exit(1)
        }
    }
}
