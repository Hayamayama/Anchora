//
//  AnchoraPrompts.swift
//  Anchora
//
//  Every prompt and system instruction Anchora sends, in one place.  Keeping
//  them out of the view controller makes the reading behaviour reviewable
//  without reading AppKit layout code.
//

import Foundation

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
         Write every answer in Markdown, and keep the structure proportional to the answer: a reply of one or two         sentences is a single paragraph with no heading and no list. For anything longer, use "## " and "### " headings         for sections, "- " for unordered points, "1. " for ordered steps, **bold** for the few terms the reader should         carry away, `backticks` for identifiers, symbols, units, and gene or variable names, and "> " for a sentence         quoted verbatim from the PDF. Never wrap a whole answer in a code fence, and never use a Markdown table —         present tabular material as a list instead. Write the [PDF p. X] citation exactly in that form; it is literal         text, not a Markdown link.
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
            return "Select text, Option-drag for OCR, or Command-Option-drag to send an image region. Your conversation stays here "
                + "while the PDF remains in view."
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

    @objc public static func quickActionTitles(profile: AnchoraReadingProfile) -> [String] {
        switch profile {
        case .scientific:
            return ["Paper", "Question", "Hypothesis", "Methods", "Figure", "Evidence"]
        case .study:
            return ["Explain", "Translate", "Clinical"]
        }
    }

    @objc public static func quickActionTooltips(profile: AnchoraReadingProfile) -> [String] {
        switch profile {
        case .scientific:
            return ["Rebuild the paper's argument as a navigable map",
                    "Research problem, gap, and the precise question",
                    "The hypothesis, and what would support it",
                    "Design, groups, controls, outcomes, and analysis",
                    "Axes, units, controls, and what the figure can establish",
                    "An evidence chain: direct result, author interpretation, inference, and what remains unproven"]
        case .study:
            return ["Explain this step by step",
                    "Translate into the configured response language",
                    "Clinical relevance and practical implications"]
        }
    }

    @objc public static func composerPlaceholder(profile: AnchoraReadingProfile) -> String {
        (profile == .scientific) ? "Ask about this paper…" : "Ask about this selection…"
    }

    /// The compact label shown in chat for a whole-document scientific action.
    @objc public static func scientificQuickActionDisplayTitle(tag: Int) -> String {
        switch tag {
        case 0: return "Build Paper Map"
        case 1: return "Research Question"
        case 2: return "Main Hypothesis"
        case 3: return "Methods"
        case 4: return "Figure"
        default: return "Evidence Chain"
        }
    }

    @objc public static func scientificQuickActionPrompt(tag: Int) -> String {
        switch tag {
        case 0:
            return paperMapPrompt
        case 1:
            return "What research problem is this paper studying? State the clinical/scientific gap, the authors' objective, and the "
                + "precise research question. Distinguish explicit statements from your inference."
        case 2:
            return "Identify the main hypothesis or hypotheses. State the predicted relationship/effect, what result would support it, "
                + "and whether the hypothesis is explicitly stated or inferred from the study design."
        case 3:
            return "Explain the research methods and experimental methods: design, participants/samples, groups or controls, "
                + "intervention/manipulation, measured outcomes, timing, and analysis. Flag missing details rather than inventing them."
        case 4:
            return "Interpret this figure rigorously. Explain the x-axis and y-axis, units, groups/conditions, controls, "
                + "symbols/error bars/statistical annotations, the observed pattern, the authors' claim, and what this figure alone can "
                + "and cannot establish. If an axis or label is not legible, say so."
        default:
            return "What does this evidence demonstrate? Separate: direct result, authors' interpretation, what is a reasonable "
                + "inference, and what remains unproven. Do not turn association into causation without an appropriate design."
        }
    }

    @objc public static func studyQuickActionPrompt(tag: Int) -> String {
        switch tag {
        case 1:
            return "Translate this into the configured response language. Preserve technical terms where helpful; if the source is "
                + "already in that language, provide a clear language-native paraphrase instead."
        case 2:
            return "Explain the clinical relevance and practical implications of this."
        default:
            return "Explain this clearly, step by step, for study."
        }
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
