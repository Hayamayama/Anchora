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
        let url = documentURL(forPath: documentPath)
        var file = read(DocumentFile.self, at: url) ?? DocumentFile(path: documentPath, title: title)
        file.path = documentPath
        file.title = title
        if file.bookmark == nil {
            file.bookmark = try? URL(fileURLWithPath: documentPath)
                .bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        file.maps[String(kindRawValue)] = AnchoraSavedMap(response: response, kindRawValue: kindRawValue)
        write(file, to: url)
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
}
