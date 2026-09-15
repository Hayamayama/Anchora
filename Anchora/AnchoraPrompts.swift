//
//  AnchoraPrompts.swift
//  Anchora
//
//  Every prompt and system instruction Anchora sends, in one place.  Keeping
//  them out of the view controller makes the reading behaviour reviewable
//  without reading AppKit layout code.
//

import Foundation

/// What a quick action does, independent of where it is offered.
///
/// Actions live in two places now -- the composer row and the ``•••``
/// menu -- so dispatching on a row index would make a menu item's meaning
/// depend on how many buttons the row happens to be showing.
@objc public enum AnchoraQuickAction: Int {
    case explain = 0
    case recall = 1
    case quiz = 2
    case translate = 3
    case clinical = 4
    case studyMap = 5
    case paperMap = 6
    case researchQuestion = 7
    case hypothesis = 8
    case methods = 9
    case figure = 10
    case evidence = 11
}

/// What an action needs in front of it before it can be asked.
@objc public enum AnchoraActionScope: Int {
    /// What the reader has selected right now.
    case selection = 0
    /// The page the reader is on, sent as a rendered image.
    case page = 1
    /// The complete PDF.
    case document = 2
}

@objc(AnchoraPrompts)
public final class AnchoraPrompts: NSObject {

    // MARK: - System instructions

    private static let studyInstructions = """
        You are Anchora, a concise study assistant. Treat supplied PDF context as the primary source for questions about this document. \
        You may also use reliable general knowledge when it helps answer the user's question. Clearly distinguish claims supported by \
        the PDF from your additional explanation; do not invent PDF citations or claim the PDF says something it does not. For every \
        paragraph that relies on supplied PDF context, end the paragraph with an inline citation in the exact form [PDF p. X], using \
        only the supplied source page labels. Do not attach a PDF citation to general knowledge. Continue the current PDF conversation naturally.
        """

    private static let scientificInstructions = """
        You are Anchora Scientific, a rigorous paper-reading assistant. Treat supplied PDF context as the primary source and help the \
        user reconstruct the paper's argument: research problem, gap, objective, hypothesis, methods, figures, evidence, conclusions, \
        and limitations. For each conclusion, distinguish exactly four levels when relevant: (1) direct result in the supplied material, \
        (2) the authors' interpretation, (3) a reasonable inference, and (4) what remains unproven. Never turn correlation into \
        causation, an observed result into a mechanism, or an authors' claim into established fact without sufficient design and \
        evidence. When interpreting a figure, explicitly cover x-axis, y-axis, units, groups/controls, uncertainty or statistics, \
        observed pattern, author claim, and limits of that figure. Say 'not stated or unclear' whenever the supplied material does not \
        support an answer. Do not invent PDF citations or claim the PDF says something it does not. For every paragraph that relies on \
        supplied PDF context, end the paragraph with an inline citation in the exact form [PDF p. X], using only supplied source page \
        labels. Do not attach a PDF citation to general knowledge. Use a thorough, evidence-first structure; do not omit requested \
        sections merely to be brief.
        """

    private static let webVerificationInstructions = """
         Web verification is enabled. Before answering, always use web search at least once to check relevant factual or current claims. \
        Prefer primary and authoritative sources. Clearly distinguish PDF-grounded claims, web-verified claims, and your own \
        explanation. Never invent a source or citation.
        """

    /// Answers are rendered as Markdown in the sidebar.  The restrictions are
    /// not stylistic: tables are not rendered as tables, a fenced whole answer
    /// would render as one grey code block, and the citation format has to stay
    /// literal so the Paper Map can still resolve it.
    private static let formattingInstructions = """
         Write every answer in Markdown, and keep the structure proportional to the answer: a reply of one or two sentences \
        is a single paragraph with no heading and no list. For anything longer, use "## " and "### " headings for sections, \
        "- " for unordered points, "1. " for ordered steps, **bold** for the few terms the reader should carry away, \
        `backticks` for identifiers, symbols, units, and gene or variable names, and "> " for a sentence quoted verbatim \
        from the PDF. Never wrap a whole answer in a code fence, and never use a Markdown table — present tabular material \
        as a list instead. Write the [PDF p. X] citation exactly in that form; it is literal text, not a Markdown link.
        """

    private static func languageInstruction(_ language: AnchoraResponseLanguage) -> String {
        switch language {
        case .traditionalChinese:
            return " Respond entirely in Traditional Chinese, while retaining essential English technical terms in parentheses when "
                + "that improves precision. This applies even when the source material or question is in English."
        case .english:
            return " Respond entirely in clear English. Preserve original technical terms when useful."
        }
    }

    @objc public static func systemInstructions(profile: AnchoraReadingProfile,
                                                language: AnchoraResponseLanguage,
                                                webVerification: Bool) -> String {
        var instructions = (profile == .scientific) ? scientificInstructions : studyInstructions
        instructions += formattingInstructions
        instructions += languageInstruction(language)
        if webVerification {
            instructions += webVerificationInstructions
        }
        return instructions
    }

    // MARK: - User prompt

    @objc public static func userPrompt(question: String,
                                        sourceText: String?,
                                        sourceDescription: String) -> String {
        guard let sourceText, sourceText.isEmpty == false else {
            return "Question: \(question)"
        }
        return "PDF source page(s): \(sourceDescription)\nPDF context:\n\(sourceText)\n\nQuestion: \(question)"
    }

    // MARK: - Welcome

    @objc public static func welcomeMessage(profile: AnchoraReadingProfile) -> String {
        switch profile {
        case .scientific:
            return "Scientific Reading is ready. Select paper text, use Command-Option-drag on a figure, or choose Build Paper Map "
                + "(PDF) from •••. I will separate direct evidence, author interpretation, and what remains unproven."
        case .study:
            return "Select text and ask, or Option-drag for OCR. When you have finished a page: write one sentence from memory "
                + "and press Recall to see what you got wrong, or press Quiz to be asked about it."
        }
    }

    // MARK: - Context and status messages

    /// What the CONTEXT card shows with nothing selected.
    @objc public static func emptyContextMessage(profile: AnchoraReadingProfile) -> String {
        (profile == .scientific)
            ? "Select paper text, or capture a figure with Command-Option-drag."
            : "Select text in the PDF to give AI context."
    }

    @objc public static let recognizingSelectionMessage = "Reading selected text with OCR…"
    @objc public static let recognizingRegionMessage = "Reading selected area with OCR…"
    @objc public static let recognitionFailureMessage =
        "This PDF’s text layer could not be read. OCR could not recover this selection; try selecting a larger area."
    @objc public static let imageReadyMessage = "Image ready — ask AI about this diagram, chart, or slide region."
    @objc public static let imageCaptureFailureMessage =
        "Could not capture this PDF area as an image. Try a smaller region."
    @objc public static let pageRenderFailureMessage = "I could not render this page as an image."

    @objc public static let selectionHint =
        "Select text, Option-drag for OCR, or Command-Option-drag to send an image region. "
        + "After the first question, you can ask a follow-up without selecting again."
    @objc public static let recognitionInProgressHint =
        "I’m still reading this selection with OCR. Try again in a moment."

    @objc public static func pageAttachedMessage(pageNumber: Int) -> String {
        "Page \(pageNumber) image attached for visual summary"
    }

    @objc public static func documentAttachedMessage(pageCount: Int) -> String {
        "Complete PDF attached: \(pageCount) pages"
    }

    @objc public static let regionImageContextText = "A visual region of the PDF is attached."
    @objc public static let pageImageContextText = "A complete rendered image of this PDF page is attached."
    @objc public static let documentContextText = "The complete original PDF is attached."

    /// The phase shown in the streaming bubble.  A full-PDF upload can take
    /// long enough that silence reads as a hang.
    @objc public static func preparingStatus(hasFile: Bool, hasImage: Bool) -> String {
        if hasFile { return "Preparing the complete PDF…" }
        if hasImage { return "Preparing the image…" }
        return "Sending your question…"
    }

    @objc public static func sendingStatus(hasFile: Bool, hasImage: Bool) -> String {
        if hasFile { return "Uploading PDF to Anchora…" }
        if hasImage { return "Sending image to Anchora…" }
        return "Waiting for Anchora…"
    }

    @objc public static let stoppedMessage = "Stopped. You can ask another question whenever you’re ready."

    // MARK: - Quick actions

    /// The row is the reading loop: what a reader presses on nearly every
    /// page.  Everything a document needs only once, and every occasional
    /// lens, is one level down in ``•••`` instead -- a row of six buttons is
    /// a row nobody reads.
    private static func rowActions(profile: AnchoraReadingProfile) -> [AnchoraQuickAction] {
        switch profile {
        case .scientific:
            return [.methods, .figure, .evidence]
        case .study:
            return [.explain, .recall, .quiz]
        }
    }

    /// The profile's remaining actions, offered in the ``•••`` menu.  Paper
    /// map is absent deliberately: ``•••`` already builds it as this
    /// profile's whole-PDF summary, and listing it twice was the duplication
    /// that pushed the row to six buttons in the first place.
    @objc(overflowActionsWithProfile:)
    public static func overflowActions(profile: AnchoraReadingProfile) -> [NSNumber] {
        let actions: [AnchoraQuickAction]
        switch profile {
        case .scientific:
            actions = [.researchQuestion, .hypothesis]
        case .study:
            actions = [.studyMap, .translate, .clinical]
        }
        return actions.map { NSNumber(value: $0.rawValue) }
    }

    /// Which action the row's nth button performs.
    @objc(rowActionWithProfile:index:)
    public static func rowAction(profile: AnchoraReadingProfile, index: Int) -> AnchoraQuickAction {
        let actions = rowActions(profile: profile)
        return actions.indices.contains(index) ? actions[index] : .explain
    }

    @objc public static func quickActionTitles(profile: AnchoraReadingProfile) -> [String] {
        rowActions(profile: profile).map(title(for:))
    }

    @objc public static func quickActionTooltips(profile: AnchoraReadingProfile) -> [String] {
        rowActions(profile: profile).map(tooltip(for:))
    }

    /// The button label: short, because three of these share the row's width.
    @objc(titleForAction:)
    public static func title(for action: AnchoraQuickAction) -> String {
        switch action {
        case .explain: return "Explain"
        case .recall: return "Recall"
        case .quiz: return "Quiz"
        case .translate: return "Translate"
        case .clinical: return "Clinical"
        case .studyMap: return "Study map"
        case .paperMap: return "Paper"
        case .researchQuestion: return "Question"
        case .hypothesis: return "Hypothesis"
        case .methods: return "Methods"
        case .figure: return "Figure"
        case .evidence: return "Evidence"
        }
    }

    /// The ``•••`` entry, where there is room to say what the action is for.
    @objc(menuTitleForAction:)
    public static func menuTitle(for action: AnchoraQuickAction) -> String {
        switch action {
        case .explain: return "Explain This Selection"
        case .recall: return "Check My Recall of This Page"
        case .quiz: return "Quiz Me on This Page"
        case .translate: return "Translate This Selection"
        case .clinical: return "Clinical Relevance"
        case .studyMap: return "Build a Study Map"
        case .paperMap: return "Build Paper Map (PDF)"
        case .researchQuestion: return "Research Question"
        case .hypothesis: return "Main Hypothesis"
        case .methods: return "Methods"
        case .figure: return "Interpret This Figure"
        case .evidence: return "Evidence Chain"
        }
    }

    /// What the transcript shows as the question.  A reader scrolling back
    /// should see what they asked, not the paragraph of instructions that
    /// went with it.
    @objc(displayTitleForAction:)
    public static func displayTitle(for action: AnchoraQuickAction) -> String {
        switch action {
        case .explain: return "Explain this"
        case .recall: return "Check my recall"
        case .quiz: return "Quiz me on this page"
        case .translate: return "Translate this"
        case .clinical: return "Clinical relevance"
        case .studyMap: return studyMapTitle
        case .paperMap: return "Build Paper Map"
        case .researchQuestion: return "Research Question"
        case .hypothesis: return "Main Hypothesis"
        case .methods: return "Methods"
        case .figure: return "Figure"
        case .evidence: return "Evidence Chain"
        }
    }

    @objc(tooltipForAction:)
    public static func tooltip(for action: AnchoraQuickAction) -> String {
        switch action {
        case .explain: return "Explain the selection step by step"
        case .recall: return "Write one sentence from memory first; Anchora tells you what you got wrong and what you missed"
        case .quiz: return "Two or three questions on this page, marked after you answer them"
        case .translate: return "Translate into the configured response language"
        case .clinical: return "Clinical relevance and practical implications"
        case .studyMap: return "Plan how to study this whole PDF: what order, what to focus on, what to skip"
        case .paperMap: return "Rebuild the paper's argument as a navigable map"
        case .researchQuestion: return "Research problem, gap, and the precise question"
        case .hypothesis: return "The hypothesis, and what would support it"
        case .methods: return "Design, groups, controls, outcomes, and analysis"
        case .figure: return "Axes, units, controls, and what the figure can establish"
        case .evidence: return "An evidence chain: direct result, author interpretation, inference, and what remains unproven"
        }
    }

    @objc(scopeForAction:)
    public static func scope(for action: AnchoraQuickAction) -> AnchoraActionScope {
        switch action {
        case .recall, .quiz:
            return .page
        case .studyMap, .paperMap:
            return .document
        default:
            return .selection
        }
    }

    @objc(mapKindForAction:)
    public static func mapKind(for action: AnchoraQuickAction) -> AnchoraMapKind {
        switch action {
        case .studyMap: return .study
        case .paperMap: return .paper
        default: return .none
        }
    }

    /// The instructions sent for an action.  ``recall`` and ``quiz`` are
    /// absent: they carry what the reader wrote, so they are built by
    /// `recallPrompt(summary:)` and graded by `quizGradingPrompt(answers:)`.
    @objc(promptForAction:)
    public static func prompt(for action: AnchoraQuickAction) -> String {
        switch action {
        case .explain:
            return "Explain this clearly, step by step, for study."
        case .recall:
            // Recall is built from what the reader wrote; there is no
            // question to ask without it.
            return ""
        case .quiz:
            return quizPrompt
        case .translate:
            return "Translate this into the configured response language. Preserve technical terms where helpful; if the source is "
                + "already in that language, provide a clear language-native paraphrase instead."
        case .clinical:
            return "Explain the clinical relevance and practical implications of this."
        case .studyMap:
            return studyMapPrompt
        case .paperMap:
            return paperMapPrompt
        case .researchQuestion:
            return "What research problem is this paper studying? State the clinical/scientific gap, the authors' objective, and the "
                + "precise research question. Distinguish explicit statements from your inference."
        case .hypothesis:
            return "Identify the main hypothesis or hypotheses. State the predicted relationship/effect, what result would support it, "
                + "and whether the hypothesis is explicitly stated or inferred from the study design."
        case .methods:
            return "Explain the research methods and experimental methods: design, participants/samples, groups or controls, "
                + "intervention/manipulation, measured outcomes, timing, and analysis. Flag missing details rather than inventing them."
        case .figure:
            return "Interpret this figure rigorously. Explain the x-axis and y-axis, units, groups/conditions, controls, "
                + "symbols/error bars/statistical annotations, the observed pattern, the authors' claim, and what this figure alone can "
                + "and cannot establish. If an axis or label is not legible, say so."
        case .evidence:
            return "What does this evidence demonstrate? Separate: direct result, authors' interpretation, what is a reasonable "
                + "inference, and what remains unproven. Do not turn association into causation without an appropriate design."
        }
    }

    @objc public static func composerPlaceholder(profile: AnchoraReadingProfile) -> String {
        (profile == .scientific) ? "Ask about this paper…" : "Ask about this selection…"
    }

    // MARK: - Recall and quiz

    /// Both of these exist for one reason: reading a page produces no signal
    /// about whether it was understood.  They are the two cheapest ways to
    /// generate one -- say it back, or be asked.

    /// The reader writes from memory, then the model marks the difference.
    /// Harder to fool than a quiz, because there is nothing to recognise.
    @objc public static func recallPrompt(summary: String) -> String {
        """
        This is what I can recall of this page, written from memory before rereading it:

        \(summary)

        Report the difference between that and the page. Do not summarise the page. Use exactly these four parts:

        1. **Right** -- what I had correct. Name it; do not explain it back to me.
        2. **Wrong** -- every claim of mine this page contradicts, each with what the page actually says and its citation.
        3. **Missed** -- only what matters for understanding this page, not everything else printed on it. If I missed \
        nothing important, say so in one line.
        4. **Fix first** -- one sentence naming the single thing to go back to.

        Judge the idea, not the wording: a correct understanding in loose or informal phrasing is correct, and a fluent \
        sentence that gets the mechanism backwards is not. Do not open with praise, and do not soften part 2 -- being told \
        plainly where I am wrong is the entire point of this.
        """
    }

    @objc public static let recallNeedsSummaryMessage =
        "Write what you remember of this page in the ask bar first — one or two sentences, without looking — then press Recall. "
        + "The comparison is only worth anything if you write it from memory."

    /// Questions only.  A page's own wording is the wrong thing to test: it
    /// can be recognised without being understood, which is the failure this
    /// feature exists to catch.
    @objc public static let quizPrompt = """
        Ask me two or three questions about this page, then stop. Do not answer them, do not hint at the answers, and do not \
        summarise the page first. Output the numbered questions and nothing else before them.

        Test whether I can use this material, not whether I can remember how it was worded. Prefer a question that makes me \
        apply it to a concrete case, tell two similar things apart, predict what changes when a condition changes, or say why \
        something is so. Never ask a question whose answer is a phrase that can be copied off the page, and never ask about \
        wording, layout, or which slide something appeared on. Keep every question answerable from this page alone.

        Number them 1., 2., 3., one sentence each. Then finish with a single line telling me to type my answers in the ask \
        bar and send them for marking.
        """

    /// The reader's answers come back through the ask bar; the page is
    /// attached again so the marking is checked against the material rather
    /// than against the model's memory of its own questions.
    @objc public static func quizGradingPrompt(answers: String) -> String {
        """
        These are my answers to the questions you just asked, in order:

        \(answers)

        Mark them against the attached page. Take each question in turn, and for each one: say what I got right, then state \
        exactly what is wrong or missing rather than a softened version of it, then give the answer I should have given in \
        one or two sentences with its citation. Where I answered correctly, say so in a single line and add nothing.

        If I answered fewer questions than you asked, mark the ones I answered and give the answer to the rest. Finish with \
        one line: the single thing to reread and its page, or that there is nothing to reread.
        """
    }

    @objc public static let quizAnswerPlaceholder = "Type your answers here, then Send…"

    @objc public static func quizDisplayTitle(pageNumber: Int) -> String {
        "Quiz me on page \(pageNumber)"
    }

    // MARK: - Paper map

    /// The exact headings here must stay in sync with `AnchoraPaperMap`'s
    /// section patterns; the navigator is built by parsing this structure back
    /// out of the response.
    @objc public static let paperMapPrompt = """
        Build a complete Paper map for this paper. Return exactly these Markdown H2 headings, in this exact English spelling even if \
        the response language is Chinese: ## Research problem and gap; ## Objective; ## Main hypothesis / research question; \
        ## Study and experimental methods; ## Key figures and evidence; ## What the paper directly demonstrates; \
        ## Authors' interpretation; ## Limitations and unanswered questions. Under each applicable heading, explicitly label evidence \
        as Direct evidence:, Author interpretation:, Reasonable inference:, and Unproven / limitation:. For every Direct evidence \
        item, include a separate line in the exact form Source quote: "a short verbatim quote from the PDF" [PDF p. X]. The quote must \
        be 8-28 words copied exactly from the cited page, so it can be selected in the PDF. Use the PDF text and visuals, cite the \
        relevant page for every PDF-grounded claim, and say 'not stated or unclear' rather than guessing.
        """

    /// A study plan, not a summary.  The reader has a deck or a chapter in
    /// front of them and wants to know how to work through it.
    @objc public static let studyMapPrompt = """
        Design a study plan for this document: how to learn it efficiently and well. This is not a summary of the content.

        First work out what kind of material this is -- lecture slides, a textbook chapter, a handout, a problem set -- and \
        what a reader is expected to be able to do once they have studied it.

        Then return between five and ten Markdown H2 sections, numbered, in the order they should be studied. Name each \
        heading for what is learned there rather than copying the slide titles. Under each heading write a Markdown bullet \
        list, one bullet per line, of exactly these:

        - Pages: the pages it covers, written as [PDF p. X] or [PDF p. X-Y], using only page labels that exist in this document
        - Goal: what the reader should be able to do after this block, phrased as an action
        - Key terms: the few terms that must be understood, in `backticks`
        - How to study it: what to actually do with these pages -- read closely, skim, redraw the diagram, memorise, work examples
        - Trap: the mistake people usually make here, when there is an obvious one

        Order the blocks by what depends on what, not by the order the pages happen to fall in, and say so when you \
        deliberately send the reader out of order.

        Finish with two more H2 sections: one giving the shortest useful path for a reader who is short of time, naming the \
        pages to read; and one headed exactly "## \(AnchoraStudyMap.selfTestHeading)", in this exact English spelling even \
        if the response language is Chinese, listing as a numbered list the questions the reader should be able to answer \
        from memory afterwards.

        Cite pages for everything you say the document covers, and say it is not covered rather than inventing material.
        """

    @objc public static let studyMapTitle = "Build a study map"

    // MARK: - Summaries

    @objc public static func pageSummaryPrompt(profile: AnchoraReadingProfile) -> String {
        switch profile {
        case .scientific:
            return "Analyze this complete paper page, including its visual structure. Identify any research claim, methods, result, "
                + "figure/table evidence, and limitations visible on the page. For every figure, explain axes, groups, and what it can "
                + "establish."
        case .study:
            return "Study this complete PDF page, including diagrams, tables, figures, and layout. Summarize the key ideas, important "
                + "terms, and 3 concise takeaways."
        }
    }

    @objc public static func documentSummaryPrompt(profile: AnchoraReadingProfile) -> String {
        switch profile {
        case .scientific:
            return paperMapPrompt
        case .study:
            return "Create a study-oriented summary of this complete PDF. Use both its text and visuals. Organize it by topic, "
                + "identify core concepts and high-yield details, and finish with a short review checklist. Cite page numbers for "
                + "major sections."
        }
    }

    @objc public static func documentSummaryDisplayTitle(profile: AnchoraReadingProfile) -> String {
        (profile == .scientific) ? "Build a Paper map for this PDF" : "Summarize this PDF"
    }
}
