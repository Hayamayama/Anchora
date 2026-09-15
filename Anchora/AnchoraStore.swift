//
//  AnchoraStore.swift
//  Anchora
//
//  Anchora's own storage, for the things a PDF cannot hold.
//
//  Annotations belong in the PDF, where other readers and other apps can see
//  them; that is why Pin writes standard annotations rather than a private
//  format.  But a study plan is about the document without being part of it,
//  and a thought caught mid-page is not about the document at all.  Those have
//  nowhere to go, so they come here: JSON under Application Support, written
//  atomically, one file for the inbox and one per document.
//
//  Documents are keyed by path rather than by content, because Anchora edits
//  the PDFs it reads -- saving a highlight rewrites the bytes, and a content
//  hash would orphan the map that was just built.  The cost is that moving a
//  file loses its saved map; the bookmark stored alongside each record exists
//  so that can be repaired later without a migration.
//

import Foundation
import CryptoKit

/// One thought, caught while reading.
@objc(AnchoraNote)
public final class AnchoraNote: NSObject, Codable, Identifiable {

    @objc public let id: String
    @objc public let text: String
    @objc public let created: Date
    @objc public let isDone: Bool
    /// Where the reader was when they wrote it.  Recorded because "check this
    /// against the earlier figure" is worthless a day later without it.
    @objc public let sourceTitle: String?
    /// One-based, as the reader sees it; zero when there was no page.
    @objc public let sourcePage: Int

    init(id: String = UUID().uuidString,
         text: String,
         created: Date = Date(),
         isDone: Bool = false,
         sourceTitle: String? = nil,
         sourcePage: Int = 0) {
        self.id = id
        self.text = text
        self.created = created
        self.isDone = isDone
        self.sourceTitle = sourceTitle
        self.sourcePage = sourcePage
        super.init()
    }

    func byMarking(done: Bool) -> AnchoraNote {
        AnchoraNote(id: id, text: text, created: created, isDone: done,
                    sourceTitle: sourceTitle, sourcePage: sourcePage)
    }

    /// "p. 14 of Respiratory physiology", or just the document, or nothing.
    public var sourceDescription: String? {
        guard let sourceTitle, sourceTitle.isEmpty == false else { return nil }
        return sourcePage > 0 ? "p. \(sourcePage) · \(sourceTitle)" : sourceTitle
    }
}

/// A map that was paid for once and should not have to be paid for again.
@objc(AnchoraSavedMap)
public final class AnchoraSavedMap: NSObject, Codable {

    @objc public let response: String
    /// The raw value of `AnchoraMapKind`; stored as an integer so the enum can
    /// gain cases without invalidating what is already on disk.
    @objc public let kindRawValue: Int
    @objc public let savedAt: Date

    init(response: String, kindRawValue: Int, savedAt: Date = Date()) {
        self.response = response
        self.kindRawValue = kindRawValue
        self.savedAt = savedAt
        super.init()
    }
}

/// One line of a study map's self-test section, made checkable.
///
/// The `id` is derived from the question's own text rather than assigned at
/// random, so rebuilding the map -- which re-parses the same response, or a
/// revised one -- reuses the same id for any question whose wording did not
/// change.  That is what lets a checkmark survive a rebuild instead of being
/// silently reset to unchecked every time.
@objc(AnchoraChecklistItem)
public final class AnchoraChecklistItem: NSObject, Codable, Identifiable {

    @objc public let id: String
    @objc public let text: String
    @objc public let isDone: Bool

    init(id: String, text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
        super.init()
    }

    func byMarking(done: Bool) -> AnchoraChecklistItem {
        AnchoraChecklistItem(id: id, text: text, isDone: done)
    }

    static func id(forText text: String) -> String {
        AnchoraStore.documentKey(forPath: text)
    }
}

/// Something Recall or Quiz corrected, waiting to be looked at again.
///
/// The whole point of Recall and Quiz is that reading a page leaves no trace
/// of whether it was understood.  Marking one of them is itself the missing
/// trace -- but it was being thrown away the moment the transcript scrolled
/// past it.  This is that trace, kept, with a date to come back to it.
@objc(AnchoraReviewItem)
public final class AnchoraReviewItem: NSObject, Codable, Identifiable {

    @objc public let id: String
    /// Which document and page this came from -- denormalised onto the item
    /// itself, rather than left implicit in which file it is stored under, so
    /// a queue drawn from every document at once can still say where each
    /// item came from and jump back to it.
    @objc public let documentPath: String
    @objc public let sourceTitle: String
    @objc public let sourcePage: Int
    /// What produced this: "Recall check" or "Quiz", with the page.  Shown as
    /// the item's label.
    @objc public let prompt: String
    /// The full corrected or graded answer, exactly as it was shown in the
    /// transcript.  Reviewing an item later is reading this again -- there is
    /// nothing to regenerate and nothing extracted from it.
    @objc public let correction: String
    @objc public let createdAt: Date
    @objc public let dueAt: Date
    /// Index into `AnchoraStore.reviewIntervalDays`.  Advances one step when
    /// the reader says they knew it; resets to the start when they say they
    /// did not.
    @objc public let stage: Int

    init(id: String = UUID().uuidString,
         documentPath: String,
         sourceTitle: String,
         sourcePage: Int,
         prompt: String,
         correction: String,
         createdAt: Date = Date(),
         dueAt: Date,
         stage: Int = 0) {
        self.id = id
        self.documentPath = documentPath
        self.sourceTitle = sourceTitle
        self.sourcePage = sourcePage
        self.prompt = prompt
        self.correction = correction
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.stage = stage
        super.init()
    }

    func byAdvancing(stage: Int, dueAt: Date) -> AnchoraReviewItem {
        AnchoraReviewItem(id: id, documentPath: documentPath, sourceTitle: sourceTitle, sourcePage: sourcePage,
                          prompt: prompt, correction: correction, createdAt: createdAt, dueAt: dueAt, stage: stage)
    }

    /// "p. 14 · Respiratory physiology", matching how a captured thought's
    /// source reads elsewhere.
    public var sourceDescription: String {
        sourceTitle.isEmpty ? "p. \(sourcePage)" : "p. \(sourcePage) · \(sourceTitle)"
    }
}

private struct InboxFile: Codable {
    var version: Int = 1
    var notes: [AnchoraNote] = []
}

private struct DocumentFile: Codable {
    var version: Int = 1
    var path: String
    var title: String
    /// Keyed by map kind's raw value, as a string because JSON object keys are.
    var maps: [String: AnchoraSavedMap] = [:]
    var selfTestItems: [AnchoraChecklistItem] = []
    var reviewItems: [AnchoraReviewItem] = []
    /// Security-scoped bookmark, so a moved file can be re-matched later
    /// without asking the reader to rebuild anything.
    var bookmark: Data?
}

@objc(AnchoraStore)
public final class AnchoraStore: NSObject {

    @objc public static let shared = AnchoraStore(directory: AnchoraStore.defaultDirectory)

    private let directory: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Tests point this at a temporary directory; the app uses
    /// `Application Support/Anchora`.
    @objc public init(directory: URL) {
        self.directory = directory
        super.init()
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Anchora", isDirectory: true)
    }

    // MARK: - Files

    private var inboxURL: URL { directory.appendingPathComponent("inbox.json") }

    private func documentsDirectory() -> URL {
        directory.appendingPathComponent("documents", isDirectory: true)
    }

    /// A path is not a filename, and can be longer than one.  The digest keeps
    /// the key stable and short; the path itself is recorded inside the file
    /// so a record is still identifiable by hand.
    static func documentKey(forPath path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func documentURL(forPath path: String) -> URL {
        documentsDirectory().appendingPathComponent(AnchoraStore.documentKey(forPath: path) + ".json")
    }

    /// Reading returns the empty value rather than throwing: a store that has
    /// never been written to is the normal first-run state, and a file that
    /// cannot be parsed must not take the sidebar down with it.
    private func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    private func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Inbox

    /// Newest first, which is the order the reader wants to see them in: the
    /// thought written a minute ago is the one still worth acting on.
    ///
    /// Two notes caught in the same instant -- which is what a burst of
    /// Command-Shift-J looks like -- fall back to the order they were written
    /// in, so the list cannot reshuffle itself between reads.
    @objc public func notes() -> [AnchoraNote] {
        let stored = read(InboxFile.self, at: inboxURL)?.notes ?? []
        return stored.enumerated()
            .sorted { left, right in
                left.element.created == right.element.created
                    ? left.offset > right.offset
                    : left.element.created > right.element.created
            }
            .map(\.element)
    }

    @objc public func openNotes() -> [AnchoraNote] {
        notes().filter { $0.isDone == false }
    }

    @objc public func openNoteCount() -> Int {
        openNotes().count
    }

    /// Empty text is not stored: an accidental Return should leave nothing
    /// behind to tidy up.
    @discardableResult
    @objc public func addNote(text: String, sourceTitle: String?, sourcePage: Int) -> AnchoraNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let note = AnchoraNote(text: trimmed, sourceTitle: sourceTitle, sourcePage: sourcePage)
        var file = read(InboxFile.self, at: inboxURL) ?? InboxFile()
        file.notes.append(note)
        return write(file, to: inboxURL) ? note : nil
    }

    @objc public func setNote(id: String, done: Bool) {
        var file = read(InboxFile.self, at: inboxURL) ?? InboxFile()
        guard let index = file.notes.firstIndex(where: { $0.id == id }) else { return }
        file.notes[index] = file.notes[index].byMarking(done: done)
        write(file, to: inboxURL)
    }

    @objc public func deleteNote(id: String) {
        var file = read(InboxFile.self, at: inboxURL) ?? InboxFile()
        file.notes.removeAll { $0.id == id }
        write(file, to: inboxURL)
    }

    /// Clearing keeps whatever is still open: this is for tidying away what
    /// has been dealt with, not for throwing away the list.
    @objc public func deleteDoneNotes() {
        var file = read(InboxFile.self, at: inboxURL) ?? InboxFile()
        file.notes.removeAll { $0.isDone }
        write(file, to: inboxURL)
    }

    // MARK: - Maps

    @objc public func saveMap(response: String, kindRawValue: Int, documentPath: String, title: String) {
        guard response.isEmpty == false, documentPath.isEmpty == false else { return }
        var file = documentFile(forPath: documentPath, title: title)
        file.maps[String(kindRawValue)] = AnchoraSavedMap(response: response, kindRawValue: kindRawValue)
        write(file, to: documentURL(forPath: documentPath))
    }

    /// The most recently built map for this document, whichever kind it was.
    /// A document is usually one thing or the other, and restoring the newer
    /// of the two is what the reader last chose to look at.
    @objc public func latestMap(documentPath: String) -> AnchoraSavedMap? {
        guard documentPath.isEmpty == false else { return nil }
        let file = read(DocumentFile.self, at: documentURL(forPath: documentPath))
        return file?.maps.values.max { $0.savedAt < $1.savedAt }
    }

    @objc public func map(kindRawValue: Int, documentPath: String) -> AnchoraSavedMap? {
        guard documentPath.isEmpty == false else { return nil }
        return read(DocumentFile.self, at: documentURL(forPath: documentPath))?.maps[String(kindRawValue)]
    }

    @objc public func deleteMaps(documentPath: String) {
        guard documentPath.isEmpty == false else { return }
        try? FileManager.default.removeItem(at: documentURL(forPath: documentPath))
    }

    /// Loads a document's file, creating one if none exists yet, and setting
    /// its path/title/bookmark the same way every write path needs to.
    private func documentFile(forPath path: String, title: String) -> DocumentFile {
        var file = read(DocumentFile.self, at: documentURL(forPath: path)) ?? DocumentFile(path: path, title: title)
        file.path = path
        if title.isEmpty == false { file.title = title }
        if file.bookmark == nil {
            file.bookmark = try? URL(fileURLWithPath: path)
                .bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return file
    }

    // MARK: - Self-test checklist

    /// Replaces a document's self-test checklist with a freshly parsed one,
    /// keeping the completion state of any question whose text is unchanged.
    /// A rebuilt study map's self-test section looks, on the wire, like a
    /// brand new list every time; matching by the question's own content
    /// rather than its position is what lets a checkmark survive that.
    @objc(setSelfTestQuestions:documentPath:title:)
    public func setSelfTestQuestions(_ texts: [String], documentPath: String, title: String) {
        guard documentPath.isEmpty == false, texts.isEmpty == false else { return }
        var file = documentFile(forPath: documentPath, title: title)
        let doneByID = Dictionary(uniqueKeysWithValues: file.selfTestItems.map { ($0.id, $0.isDone) })
        file.selfTestItems = texts.map { text in
            let id = AnchoraChecklistItem.id(forText: text)
            return AnchoraChecklistItem(id: id, text: text, isDone: doneByID[id] ?? false)
        }
        write(file, to: documentURL(forPath: documentPath))
    }

    @objc(selfTestQuestionsWithDocumentPath:)
    public func selfTestQuestions(documentPath: String) -> [AnchoraChecklistItem] {
        guard documentPath.isEmpty == false else { return [] }
        return read(DocumentFile.self, at: documentURL(forPath: documentPath))?.selfTestItems ?? []
    }

    @objc(setSelfTestItemWithID:done:documentPath:)
    public func setSelfTestItem(id: String, done: Bool, documentPath: String) {
        guard documentPath.isEmpty == false else { return }
        let url = documentURL(forPath: documentPath)
        var file = read(DocumentFile.self, at: url) ?? DocumentFile(path: documentPath, title: "")
        guard let index = file.selfTestItems.firstIndex(where: { $0.id == id }) else { return }
        file.selfTestItems[index] = file.selfTestItems[index].byMarking(done: done)
        write(file, to: url)
    }

    // MARK: - Review queue

    /// The schedule a review item advances through: a day, then three, then a
    /// week, then two weeks, then a month.  Fixed and simple on purpose --
    /// this is not spaced repetition tuned per item, it is "come back to this
    /// again soon, then less often once it stops being wrong."
    @objc public static let reviewIntervalDays: [Int] = [1, 3, 7, 14, 30]

    private static func dueDate(forStage stage: Int) -> Date {
        let days = reviewIntervalDays[min(max(stage, 0), reviewIntervalDays.count - 1)]
        return Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }

    /// Enqueues a Recall or Quiz correction for later review.  Every
    /// completed correction is queued, not only the ones with something
    /// wrong in them -- telling those apart would mean parsing the model's
    /// own prose, and a review of something already understood costs nothing
    /// but a moment, while missing a real correction costs the whole point of
    /// this feature.
    @discardableResult
    @objc(addReviewItemWithPrompt:correction:documentPath:title:sourcePage:)
    public func addReviewItem(prompt: String, correction: String, documentPath: String,
                              title: String, sourcePage: Int) -> AnchoraReviewItem? {
        guard correction.isEmpty == false, documentPath.isEmpty == false else { return nil }
        let item = AnchoraReviewItem(documentPath: documentPath, sourceTitle: title, sourcePage: sourcePage,
                                     prompt: prompt, correction: correction, dueAt: AnchoraStore.dueDate(forStage: 0))
        var file = documentFile(forPath: documentPath, title: title)
        file.reviewItems.append(item)
        write(file, to: documentURL(forPath: documentPath))
        return item
    }

    /// Every review item across every document, for a queue that does not
    /// require reopening each PDF to see what is waiting in it.
    @objc(allReviewItems)
    public func allReviewItems() -> [AnchoraReviewItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: documentsDirectory(),
                                                                       includingPropertiesForKeys: nil)
        else { return [] }
        return urls.compactMap { read(DocumentFile.self, at: $0) }.flatMap(\.reviewItems)
    }

    /// Items due now or earlier, oldest due date first -- the one that has
    /// been waiting longest is the one to look at first.
    @objc public func dueReviewItems(asOf date: Date = Date()) -> [AnchoraReviewItem] {
        allReviewItems().filter { $0.dueAt <= date }.sorted { $0.dueAt < $1.dueAt }
    }

    /// "Knew it" advances the schedule; "still shaky" resets it to the start.
    /// Items live nested inside their document's own file, so advancing one
    /// means finding that file again by the path recorded on the item.
    @objc(advanceReviewItemWithID:documentPath:gotIt:)
    public func advanceReviewItem(id: String, documentPath: String, gotIt: Bool) {
        guard documentPath.isEmpty == false else { return }
        let url = documentURL(forPath: documentPath)
        var file = read(DocumentFile.self, at: url) ?? DocumentFile(path: documentPath, title: "")
        guard let index = file.reviewItems.firstIndex(where: { $0.id == id }) else { return }
        let nextStage = gotIt ? min(file.reviewItems[index].stage + 1, AnchoraStore.reviewIntervalDays.count - 1) : 0
        file.reviewItems[index] = file.reviewItems[index].byAdvancing(stage: nextStage, dueAt: AnchoraStore.dueDate(forStage: nextStage))
        write(file, to: url)
    }

    @objc(deleteReviewItemWithID:documentPath:)
    public func deleteReviewItem(id: String, documentPath: String) {
        guard documentPath.isEmpty == false else { return }
        let url = documentURL(forPath: documentPath)
        var file = read(DocumentFile.self, at: url) ?? DocumentFile(path: documentPath, title: "")
        file.reviewItems.removeAll { $0.id == id }
        write(file, to: url)
    }
}
