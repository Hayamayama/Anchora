//
//  AnchoraHeaderView.swift
//  Anchora
//
//  The identity row and the CONTEXT card.
//

import SwiftUI

/// Carries the ••• button's frame out to the model, so the NSMenu can be
/// popped exactly under it.
private struct MoreActionsFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // Only one view reports a frame; every other child contributes the
        // default.  Overwriting unconditionally lets a later sibling erase it,
        // which is how this arrived as .zero the first time.
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct AnchoraHeaderView: View {

    @ObservedObject var model: AnchoraHeaderModel
    @State private var isShowingContext: Bool = false

    /// Fixed: nothing here wraps to an unpredictable height.  The context is
    /// one line, and the full text opens in a popover rather than pushing the
    /// header taller -- which keeps the header a constant and leaves the
    /// sidebar with one dynamic height (the composer's) instead of two.
    static let height: CGFloat = 78.0
    private static let coordinateSpace = "AnchoraHeader"

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            identityRow
            contextStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(MoreActionsFrameKey.self) { frame in
            model.setMoreActionsAnchor(frame)
        }
    }

    private var identityRow: some View {
        HStack(alignment: .top, spacing: 8.0) {
            VStack(alignment: .leading, spacing: 1.0) {
                Text(model.title)
                    .font(.system(size: 16.0, weight: .bold))
                Text(model.subtitle)
                    .font(.system(size: 11.0))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4.0)
            Picker("", selection: Binding(get: { model.isScientific },
                                          set: { model.selectProfile(scientific: $0) })) {
                Text("Study").tag(false)
                Text("Scientific").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            Button("•••") { model.onMoreActions?() }
                .controlSize(.small)
                .help("Summaries, response language, AI model, notes and API settings")
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: MoreActionsFrameKey.self,
                                           value: proxy.frame(in: .named(Self.coordinateSpace)))
                })
        }
        .padding(.horizontal, 4.0)
    }

    /// What Anchora would send if you asked right now, in one line.
    private var contextStrip: some View {
        HStack(spacing: 6.0) {
            Text(model.contextTitle)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)
            Text(model.contextSummary)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.isContextExpandable {
                Button {
                    isShowingContext.toggle()
                } label: {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 10.0))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show everything that would be sent as context")
                .popover(isPresented: $isShowingContext, arrowEdge: .bottom) {
                    contextDetail
                }
            }
        }
        .padding(.horizontal, 8.0)
        .padding(.vertical, 5.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8.0, style: .continuous))
    }

    /// Opening it is how OCR output gets checked before it is paid for, so it
    /// is selectable and roomy rather than a tooltip.
    private var contextDetail: some View {
        ScrollView(.vertical) {
            Text(model.contextText)
                .font(.system(size: 12.0))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12.0)
        }
        .frame(width: 320.0, height: 220.0)
    }
}
