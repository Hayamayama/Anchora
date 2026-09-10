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

    /// Fixed, like the composer: nothing here wraps to an unpredictable
    /// height, and the context card scrolls rather than growing.
    static let height: CGFloat = 146.0
    private static let contextHeight: CGFloat = 86.0
    private static let coordinateSpace = "AnchoraHeader"

    var body: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            identityRow
            contextCard
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

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 2.0) {
            Text(model.contextTitle)
                .font(.system(size: 10.0, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6.0)
            ScrollView(.vertical) {
                Text(model.contextText)
                    .font(.system(size: 12.0))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6.0)
            }
        }
        .padding(.vertical, 8.0)
        .frame(maxWidth: .infinity, minHeight: Self.contextHeight, maxHeight: Self.contextHeight, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12.0, style: .continuous))
    }
}
