import Foundation
import CoreGraphics

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

    expect(AnchoraPrompts.quickActionTitles(profile: .scientific).count == 6, "Scientific has six quick actions")
    expect(AnchoraPrompts.quickActionTitles(profile: .study).count == 3, "Study has three quick actions")
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
                            isPaperMap: false, status: nil)
    let second = AnchoraTurn(question: "And this?", conversationUserText: "And this?",
                             selection: nil, hasTextSelection: false, page: nil, pageRect: .zero,
                             imageDataURL: nil, sourcePageIndexes: [NSNumber(value: 8)],
                             isPaperMap: false, status: nil)

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
                           sourcePageIndexes: [], isPaperMap: false, status: "Waiting…")
    expect(turn.canPin == false, "a turn with no answer cannot be pinned")
    turn.receivedOutput = true
    expect(turn.canPin == false, "an answer with nowhere in the PDF to anchor it cannot be pinned")
}

func testTurnAccumulatesItsAnswer() {
    let turn = AnchoraTurn(question: "Explain this", conversationUserText: "Explain this",
                           selection: nil, hasTextSelection: false, page: nil, pageRect: .zero, imageDataURL: nil,
                           sourcePageIndexes: [NSNumber(value: 3)], isPaperMap: true, status: nil)
    turn.response.append("first ")
    turn.response.append("second")
    expectEqual(turn.response as String, "first second", "streamed deltas accumulate on the turn")
    expectEqual(turn.sourcePageIndexes.map(\.intValue), [3], "the turn keeps the pages it was asked about")
    expect(turn.isPaperMap, "the turn remembers it is a paper map")
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
        testMarkdownBlockKinds()
        testMarkdownNestedList()
        testMarkdownHandlesPartialStreamedText()
        testMarkdownBlockIdentityIsStable()
        testMarkdownPreservesCitations()
        testMarkdownPlainText()
        testFormattingInstructionsMatchTheRenderer()
        testTextQualityHeuristic()
        testRecognitionLanguageResolution()
        testRenderRectUnrotatedPage()
        testRenderRectSubtractsTheBoxOrigin()
        testRenderRectRotations()
        testRenderRectWholePageOnARotatedPage()
        testSelectionGenerationAdvances()
        testFinishingRecognitionKeepsItsGeneration()
        testFinishingRecognitionWithNothing()
        testSelectionContextStates()
        testTurnCannotPinWithoutAnAnchorOrAnAnswer()
        testTurnAccumulatesItsAnswer()

        if failures == 0 {
            print("AnchoraCoreTests: \(checks) checks passed")
        } else {
            print("AnchoraCoreTests: \(failures) of \(checks) checks FAILED")
            exit(1)
        }
    }
}
