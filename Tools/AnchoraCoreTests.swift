import Foundation

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
    model.beginStreamingMessage(status: "Uploading PDF to Anchora…", sourceLabel: "p. 4", sourcePageIndex: NSNumber(value: 3))
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
    model.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil)
    model.replaceStreamingMessage(with: "Stopped.")
    expectEqual(model.messages.count, 1, "stopping before any output reuses the placeholder bubble")
    expectEqual(model.messages[0].text, "Stopped.", "the placeholder shows why it stopped")

    let partial = AnchoraChatModel()
    partial.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil)
    partial.appendStreamedText("half an answer")
    partial.replaceStreamingMessage(with: "Network error: timed out")
    expectEqual(partial.messages.count, 2, "an error after partial output keeps the partial answer")
    expectEqual(partial.messages[0].text, "half an answer", "the partial answer is not destroyed")
}

func testChatPaperMapRemovesItsBubble() {
    let model = AnchoraChatModel()
    model.appendUserMessage("Build Paper Map")
    model.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil)
    model.appendStreamedText("## Objective\nlong paper map text")
    model.removeStreamingMessage()
    expectEqual(model.messages.count, 1, "a paper map's raw text leaves the transcript")
    expectEqual(model.messages[0].kind, .user, "the question that produced it stays")
}

/// Clear chat cancels the turn, but a delta already in flight can still arrive.
func testChatSurvivesClearMidStream() {
    let model = AnchoraChatModel()
    model.beginStreamingMessage(status: "Waiting…", sourceLabel: nil, sourcePageIndex: nil)
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

        if failures == 0 {
            print("AnchoraCoreTests: \(checks) checks passed")
        } else {
            print("AnchoraCoreTests: \(failures) of \(checks) checks FAILED")
            exit(1)
        }
    }
}
