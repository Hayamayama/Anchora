//
//  AnchoraChatModel.swift
//  Anchora
//
//  The chat transcript as data.  The sidebar view controller mutates this and
//  SwiftUI renders it; nothing here measures text or touches a constraint.
//

import Foundation
import Combine

public struct AnchoraChatMessage: Identifiable {

    public enum Kind {
        case user
        case assistant
        case webSources
    }

    public let id = UUID()
    public var kind: Kind
    public var text: String
    /// e.g. "p. 3, 4" — nil when the answer has no traceable PDF page.
    public var sourceLabel: String?
    public var sourcePageIndex: Int?
    /// The turn this answer came from, so it can still be pinned after later
    /// questions have moved on.  Nil for anything that is not a finished answer.
    public var turn: AnchoraTurn?
    /// True while this bubble is still showing a request phase rather than
    /// model output ("Uploading PDF to Anchora…").
    public var isPlaceholder: Bool = false

    public var senderName: String {
        switch kind {
        case .user: return "You"
        case .assistant: return "Anchora"
        case .webSources: return "Web sources"
        }
    }
}

@objc(AnchoraChatModel)
public final class AnchoraChatModel: NSObject, ObservableObject {

    @Published public private(set) var messages: [AnchoraChatMessage] = []
    /// Bumped on every mutation so the view scrolls to the newest message
    /// even when the last message's identity has not changed.
    @Published public private(set) var revision: Int = 0

    /// Called when the reader clicks an answer's PDF source chip.
    @objc public var onOpenPage: ((Int) -> Void)?
    /// Per-answer actions.  These act on the answer they were shown under, not
    /// on whatever happens to be the latest one.
    @objc public var onCopy: ((String) -> Void)?
    @objc public var onPinAnchor: ((AnchoraTurn) -> Void)?
    @objc public var onPinTextNote: ((AnchoraTurn) -> Void)?

    private var streamingIndex: Int?

    /// A cancel arriving between a clear and a late delta can leave the index
    /// pointing past the end, so every use is validated rather than trusted.
    private var validStreamingIndex: Int? {
        guard let index = streamingIndex, messages.indices.contains(index) else { return nil }
        return index
    }

    private func touch() {
        revision &+= 1
    }

    // MARK: - Appending

    @objc public func appendUserMessage(_ text: String) {
        messages.append(AnchoraChatMessage(kind: .user, text: text))
        touch()
    }

    @objc public func appendAssistantMessage(_ text: String) {
        messages.append(AnchoraChatMessage(kind: .assistant, text: text))
        touch()
    }

    @objc public func appendWebSourcesMessage(_ text: String) {
        messages.append(AnchoraChatMessage(kind: .webSources, text: text))
        touch()
    }

    // MARK: - The streaming turn

    /// Adds the assistant bubble a turn will stream into.  It shows `status`
    /// until the first output arrives, so a long full-PDF upload never leaves
    /// an empty bubble on screen.
    @objc public func beginStreamingMessage(status: String,
                                            sourceLabel: String?,
                                            sourcePageIndex: NSNumber?,
                                            turn: AnchoraTurn?) {
        messages.append(AnchoraChatMessage(kind: .assistant,
                                           text: status,
                                           sourceLabel: sourceLabel,
                                           sourcePageIndex: sourcePageIndex?.intValue,
                                           turn: turn,
                                           isPlaceholder: true))
        streamingIndex = messages.count - 1
        touch()
    }

    @objc public func updateStreamingStatus(_ status: String) {
        guard let index = validStreamingIndex, messages[index].isPlaceholder else { return }
        messages[index].text = status
        touch()
    }

    @objc public func appendStreamedText(_ text: String) {
        guard text.isEmpty == false, let index = validStreamingIndex else { return }
        if messages[index].isPlaceholder {
            messages[index].text = text
            messages[index].isPlaceholder = false
        } else {
            messages[index].text += text
        }
        touch()
    }

    /// Replaces whatever the streaming bubble is showing — used for "Stopped."
    /// and for error text.  Falls back to a fresh message when the turn had
    /// already produced output.
    @objc public func replaceStreamingMessage(with text: String) {
        guard let index = validStreamingIndex else {
            streamingIndex = nil
            if text.isEmpty == false { appendAssistantMessage(text) }
            return
        }
        if messages[index].isPlaceholder {
            messages[index].text = text
            messages[index].isPlaceholder = false
            streamingIndex = nil
            touch()
        } else {
            streamingIndex = nil
            appendAssistantMessage(text)
        }
    }

    /// Drops the streaming bubble entirely.  A Paper Map is presented in its
    /// own navigator, so its raw text should not also fill the transcript.
    @objc public func removeStreamingMessage() {
        guard let index = validStreamingIndex else { streamingIndex = nil; return }
        messages.remove(at: index)
        streamingIndex = nil
        touch()
    }

    @objc public func endStreaming() {
        streamingIndex = nil
    }

    // MARK: - Clearing and lookup

    @objc public func clear() {
        messages.removeAll()
        streamingIndex = nil
        touch()
    }

    /// Used to avoid writing the same "select some text first" hint twice.
    @objc public func containsText(_ text: String) -> Bool {
        messages.contains { $0.text.contains(text) }
    }
}
