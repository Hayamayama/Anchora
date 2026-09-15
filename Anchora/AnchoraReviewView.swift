//
//  AnchoraReviewView.swift
//  Anchora
//
//  One card per due item: what it was, the full correction as it was shown
//  the first time, and two buttons -- because the only two facts that matter
//  on a second look are whether it landed this time or not.
//

import SwiftUI

struct AnchoraReviewView: View {

    @ObservedObject var model: AnchoraReviewModel

    var body: some View {
        Group {
            if model.dueItems.isEmpty {
                empty
            } else {
                list
            }
        }
        .padding(.horizontal, 8.0)
        .padding(.vertical, 8.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Text(model.notYetDueCount > 0 ? "Nothing due yet." : "Nothing queued.")
                .font(.system(size: 12.0, weight: .medium))
            Text(model.notYetDueCount > 0
                 ? "\(model.notYetDueCount) waiting for a later date."
                 : "Recall and Quiz add what they correct here automatically, once you use them.")
                .font(.system(size: 11.0))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6.0)
    }

    private var list: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10.0) {
                ForEach(model.dueItems) { item in
                    card(item)
                }
                if model.notYetDueCount > 0 {
                    Text("\(model.notYetDueCount) more not due yet")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2.0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func card(_ item: AnchoraReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(alignment: .firstTextBaseline, spacing: 6.0) {
                Text(item.prompt)
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer(minLength: 4.0)
                Button {
                    model.open(item)
                } label: {
                    Text(item.sourceDescription)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Jump back to this page")
            }

            AnchoraMarkdownText(markdown: item.correction, bodySize: 12.0)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8.0) {
                Button("Still shaky") { model.markStillShaky(item) }
                    .help("Review this again tomorrow")
                Button("Knew it") { model.markKnewIt(item) }
                    .keyboardShortcut(.defaultAction)
                    .help("Push this further out")
                Spacer(minLength: 4.0)
                Button {
                    model.delete(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.0))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from the queue")
            }
            .controlSize(.small)
        }
        .padding(9.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8.0, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8.0, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor)))
        .textSelection(.enabled)
    }
}
