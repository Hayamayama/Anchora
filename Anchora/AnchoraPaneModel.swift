//
//  AnchoraPaneModel.swift
//  Anchora
//
//  Which of the sidebar's three faces is showing.
//
//  A map used to be a card wedged above the transcript, which meant it was
//  permanently competing with the conversation for the same sidebar: 248
//  points was too little to read a study plan in and too much to give up while
//  chatting.  They are not things to see at once -- navigating a plan and
//  asking a question are different activities -- so they take turns, and each
//  gets the whole body.
//

import Foundation
import Combine

@objc public enum AnchoraPaneTab: Int {
    case chat = 0
    case map = 1
    case inbox = 2
}

@objc(AnchoraPaneModel)
public final class AnchoraPaneModel: NSObject, ObservableObject {

    @Published public private(set) var tab: AnchoraPaneTab = .chat

    @objc public func show(_ tab: AnchoraPaneTab) {
        self.tab = tab
    }

    @objc public func showChat() { show(.chat) }
    @objc public func showMap() { show(.map) }
    @objc public func showInbox() { show(.inbox) }

    @objc public var isShowingInbox: Bool { tab == .inbox }

    /// Used when the thing a tab was showing goes away -- a cleared map, a new
    /// document -- so the sidebar never sits on an empty face.
    @objc public func leaveTabIfShowing(_ tab: AnchoraPaneTab) {
        if self.tab == tab { self.tab = .chat }
    }
}
