//
//  AnchoraInboxModel.swift
//  Anchora
//
//  The thought inbox: somewhere to put the thing you just remembered, without
//  leaving the page you are on.
//
//  This exists because the expensive part of an interruption is not the note,
//  it is the trip -- opening another app to write "look up the half-life of
//  this" costs the thread of what was being read.  So the inbox holds one line
//  at a time, takes no decisions (no project, no due date, no tags), and gives
//  the reading back immediately.
//

import Foundation
import Combine

@objc(AnchoraInboxModel)
public final class AnchoraInboxModel: NSObject, ObservableObject {

    /// The inbox is one list behind several views: a drawer in every open
    /// document's sidebar, and the ⌘⇧J panel.  They all write through the same
    /// store, so each one announces its change and the rest reread it.
    public static let didChangeNotification = Notification.Name("AnchoraInboxDidChange")

    @Published public private(set) var notes: [AnchoraNote] = []
    @Published public var draft: String = ""
    /// Completed notes stay out of the way until asked for; the list is meant
    /// to show what is still outstanding.
    @Published public var showsDone: Bool = false
    /// Bumped to ask the inbox's field to take the keyboard, the same counter
    /// trick the composer uses.
    @Published public private(set) var focusRequest: Int = 0

    private let store: AnchoraStore

    /// Asked only at the moment a note is written, so nothing has to be kept
    /// in step with the reader's scrolling.
    @objc public var sourceTitleProvider: (() -> String)?
    @objc public var sourcePageProvider: (() -> Int)?

    @objc public init(store: AnchoraStore) {
        self.store = store
        super.init()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: AnchoraInboxModel.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc public convenience override init() {
        self.init(store: AnchoraStore.shared)
    }

    // MARK: - State

    public var openNotes: [AnchoraNote] { notes.filter { $0.isDone == false } }
    public var doneNotes: [AnchoraNote] { notes.filter(\.isDone) }
    @objc public var openCount: Int { openNotes.count }

    @objc public func reload() {
        notes = store.notes()
    }

    private func changed() {
        reload()
        NotificationCenter.default.post(name: AnchoraInboxModel.didChangeNotification, object: nil)
    }

    @objc public func focusDraftField() {
        focusRequest &+= 1
    }

    // MARK: - Mutation

    /// Returns whether anything was stored, so a capture window knows whether
    /// it has something to confirm.
    @discardableResult
    @objc public func addDraft() -> Bool {
        let added = add(text: draft)
        if added { draft = "" }
        return added
    }

    @discardableResult
    @objc public func add(text: String) -> Bool {
        let note = store.addNote(text: text,
                                 sourceTitle: sourceTitleProvider?(),
                                 sourcePage: sourcePageProvider?() ?? 0)
        guard note != nil else { return false }
        changed()
        return true
    }

    public func setDone(_ note: AnchoraNote, _ done: Bool) {
        store.setNote(id: note.id, done: done)
        changed()
    }

    public func delete(_ note: AnchoraNote) {
        store.deleteNote(id: note.id)
        changed()
    }

    public func clearDone() {
        store.deleteDoneNotes()
        changed()
    }
}
