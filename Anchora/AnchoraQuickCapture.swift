//
//  AnchoraQuickCapture.swift
//  Anchora
//
//  ⌘⇧J: one line, then back to the page.
//
//  The sidebar's inbox drawer only helps if the sidebar is open and the reader
//  is willing to look away from the PDF.  The interruption this is for -- "I
//  must check that dose", "reply to Ben" -- arrives mid-paragraph, and the cost
//  of it is the trip away, not the typing.  So this is a floating panel that
//  can be summoned from anywhere in the app, takes one line, and closes.
//
//  The shortcut is a local event monitor rather than a menu item: a menu item
//  would have to be added to a nib that is localised into ten languages, and a
//  global (system-wide) hotkey would need an Input Monitoring grant that this
//  app has no other reason to ask for.  A local monitor sees only Anchora's
//  own key events and needs no permission at all.
//

import AppKit
import SwiftUI

@objc(AnchoraQuickCapture)
public final class AnchoraQuickCapture: NSObject {

    @objc public static let shared = AnchoraQuickCapture()

    private var panel: NSPanel?
    private var monitor: Any?
    private let model = AnchoraInboxModel()

    /// Where the reader was when the panel was summoned.  Installed by
    /// whichever document sidebar last had the reader's attention, and asked
    /// only at the moment a note is written.  With one window open that is
    /// exactly right; with several, the document you last touched wins, which
    /// is the useful reading of "where I am".
    @objc public var sourceTitleProvider: (() -> String)? {
        didSet { model.sourceTitleProvider = sourceTitleProvider }
    }
    @objc public var sourcePageProvider: (() -> Int)? {
        didSet { model.sourcePageProvider = sourcePageProvider }
    }

    // MARK: - Shortcut

    /// Installed once, for the whole application.
    @objc public func installShortcut() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command, .shift],
                  event.charactersIgnoringModifiers?.lowercased() == "j"
            else { return event }
            self?.toggle()
            return nil
        }
    }

    // MARK: - Panel

    @objc public func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    @objc public func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.draft = ""
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        model.focusDraftField()
    }

    @objc public func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0.0, y: 0.0, width: 420.0, height: 96.0),
                            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
                            backing: .buffered,
                            defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        // A panel that releases itself on close would take the hosting view
        // and the draft with it.
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        let hosting = NSHostingView(rootView: AnchoraQuickCaptureView(model: model) { [weak self] in
            self?.close()
        })
        panel.contentView = hosting
        return panel
    }

    /// Over the window the reader is looking at, high enough that it does not
    /// cover the middle of the page.
    private func position(_ panel: NSPanel) {
        let reference = NSApp.keyWindow ?? NSApp.mainWindow
        let bounds = reference?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        guard bounds.isEmpty == false else { return panel.center() }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: bounds.midX - size.width / 2.0,
                                     y: bounds.maxY - bounds.height * 0.28 - size.height))
    }
}

struct AnchoraQuickCaptureView: View {

    @ObservedObject var model: AnchoraInboxModel
    var onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            TextField("What just came to mind?", text: $model.draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14.0))
                .focused($focused)
                .onSubmit(save)
            Text("Return saves it to the inbox and closes. Escape discards.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16.0)
        .padding(.bottom, 14.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onExitCommand(perform: onClose)
        .onChange(of: model.focusRequest) {
            focused = true
        }
        .onAppear { focused = true }
    }

    private func save() {
        // An empty field closes rather than storing nothing, so Return is
        // always the way out.
        model.addDraft()
        onClose()
    }
}
