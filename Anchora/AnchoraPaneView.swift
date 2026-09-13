//
//  AnchoraPaneView.swift
//  Anchora
//
//  The tab strip and the body it switches.  One hosting view rather than three
//  stacked ones: the map's height used to be an Auto Layout constraint the
//  view controller recalculated by hand, and the whole mechanism disappears
//  when the body is simply whichever view is selected.
//

import SwiftUI

struct AnchoraPaneView: View {

    @ObservedObject var pane: AnchoraPaneModel
    @ObservedObject var chat: AnchoraChatModel
    @ObservedObject var map: AnchoraMapModel
    @ObservedObject var inbox: AnchoraInboxModel
    var pageLabels: [String]

    /// The strip's height, which the host adds to whatever it gives the body.
    static let stripHeight: CGFloat = 22.0

    /// A tab whose content has gone away must not stay selected.  The model is
    /// kept in step too, but resolving it here means a stale selection can
    /// never render an empty face even for one frame.
    private var selected: AnchoraPaneTab {
        (pane.tab == .map && map.isEmpty) ? .chat : pane.tab
    }

    var body: some View {
        VStack(spacing: 6.0) {
            strip
            body(for: selected)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func body(for tab: AnchoraPaneTab) -> some View {
        switch tab {
        case .chat:
            AnchoraChatView(model: chat)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .map:
            drawer { AnchoraMapView(model: map, pageLabels: pageLabels) }
        case .inbox:
            drawer { AnchoraInboxView(model: inbox) }
        }
    }

    /// The two drawers sit on a card, so it reads as something pulled out over
    /// the conversation rather than as a different screen.
    private func drawer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12.0, style: .continuous))
    }

    private var strip: some View {
        HStack(spacing: 4.0) {
            tabButton(.chat, title: "Chat", badge: 0,
                      help: "The conversation about what you are reading")
            tabButton(.map, title: map.isEmpty ? "Map" : map.shortTitle, badge: 0,
                      help: map.isEmpty
                        ? "Build a study map or a paper map first — both are in the ••• menu"
                        : "The map built for this document")
                .disabled(map.isEmpty)
            tabButton(.inbox, title: "Inbox", badge: inbox.openCount,
                      help: "Thoughts to deal with later. ⌘⇧J captures one from anywhere in Anchora")
            Spacer(minLength: 0.0)
        }
        .frame(height: Self.stripHeight)
        .padding(.horizontal, 8.0)
    }

    private func tabButton(_ tab: AnchoraPaneTab, title: String, badge: Int, help: String) -> some View {
        Button {
            pane.show(tab)
        } label: {
            HStack(spacing: 4.0) {
                Text(title)
                    .font(.system(size: 11.0, weight: selected == tab ? .semibold : .regular))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9.0, weight: .semibold))
                        .padding(.horizontal, 4.0)
                        .padding(.vertical, 1.0)
                        .background(Capsule().fill(Color.accentColor.opacity(selected == tab ? 0.9 : 0.55)))
                        .foregroundStyle(Color.white)
                }
            }
            .padding(.horizontal, 8.0)
            .padding(.vertical, 3.0)
            .background(RoundedRectangle(cornerRadius: 6.0, style: .continuous)
                .fill(selected == tab ? Color(nsColor: .controlBackgroundColor) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 6.0, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
