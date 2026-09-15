//
//  AnchoraReviewModel.swift
//  Anchora
//
//  The review queue: what Recall and Quiz corrected, waiting to be looked at
//  again.
//
//  Recall and Quiz produce a real signal -- what you got wrong, what you
//  missed -- and until now that signal was thrown away the moment the
//  transcript scrolled past it.  Every completed correction is queued here
//  automatically, across every document at once, with a simple schedule: a
//  day, then three, then a week, then longer, advancing when you say you knew
//  it and resetting when you say you did not.
//

import Foundation
import Combine

@objc(AnchoraReviewModel)
public final class AnchoraReviewModel: NSObject, ObservableObject {

    @Published public private(set) var dueItems: [AnchoraReviewItem] = []
    /// Queued but not due yet -- shown as a count, not a list, so the drawer
    /// stays about what needs attention now.
    @Published public private(set) var notYetDueCount: Int = 0

    private let store: AnchoraStore

    /// Opens the item's document (if it is not already the one on screen) and
    /// jumps to the page it came from.
    @objc public var onOpenItem: ((AnchoraReviewItem) -> Void)?

    @objc public init(store: AnchoraStore) {
        self.store = store
        super.init()
        reload()
    }

    @objc public convenience override init() {
        self.init(store: .shared)
    }

    @objc public var dueCount: Int { dueItems.count }

    @objc public func reload() {
        let all = store.allReviewItems()
        let now = Date()
        dueItems = all.filter { $0.dueAt <= now }.sorted { $0.dueAt < $1.dueAt }
        notYetDueCount = all.count - dueItems.count
    }

    // MARK: - Mutation

    public func markKnewIt(_ item: AnchoraReviewItem) {
        store.advanceReviewItem(id: item.id, documentPath: item.documentPath, gotIt: true)
        reload()
    }

    public func markStillShaky(_ item: AnchoraReviewItem) {
        store.advanceReviewItem(id: item.id, documentPath: item.documentPath, gotIt: false)
        reload()
    }

    public func delete(_ item: AnchoraReviewItem) {
        store.deleteReviewItem(id: item.id, documentPath: item.documentPath)
        reload()
    }

    public func open(_ item: AnchoraReviewItem) {
        onOpenItem?(item)
    }
}
