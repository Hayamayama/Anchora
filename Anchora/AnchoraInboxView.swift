//
//  AnchoraInboxView.swift
//  Anchora
//
//  One field, one list.  Everything a more capable task UI would add -- due
//  dates, projects, priorities -- is a decision to make at the moment of
//  writing, which is the moment the reading is interrupted.
//

import SwiftUI

struct AnchoraInboxView: View {

    @ObservedObject var model: AnchoraInboxModel
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            field
            if model.notes.isEmpty {
                empty
            } else {
                list
            }
        }
        .padding(.horizontal, 8.0)
        .padding(.vertical, 8.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.focusRequest) {
            draftFocused = true
        }
    }

    private var field: some View {
        HStack(spacing: 8.0) {
            TextField("Something to deal with later…", text: $model.draft)
                .textFieldStyle(.roundedBorder)
                .focused($draftFocused)
                .onSubmit { model.addDraft() }
            Button("Add") { model.addDraft() }
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .controlSize(.small)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Text("Nothing waiting.")
                .font(.system(size: 12.0, weight: .medium))
            Text("Press ⌘⇧J anywhere in Anchora to write one line without leaving the page you are reading.")
                .font(.system(size: 11.0))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6.0)
    }

    private var list: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2.0) {
                ForEach(model.openNotes) { note in
                    row(note)
                }
                if model.doneNotes.isEmpty == false {
                    doneSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 2.0) {
            HStack(spacing: 6.0) {
                Button(model.showsDone
                       ? "Hide \(model.doneNotes.count) done"
                       : "Show \(model.doneNotes.count) done") {
                    model.showsDone.toggle()
                }
                .buttonStyle(.link)
                if model.showsDone {
                    Button("Clear them") { model.clearDone() }
                        .buttonStyle(.link)
                }
            }
            .font(.system(size: 10.5))
            .padding(.top, 8.0)

            if model.showsDone {
                ForEach(model.doneNotes) { note in
                    row(note)
                }
            }
        }
    }

    private func row(_ note: AnchoraNote) -> some View {
        HStack(alignment: .top, spacing: 7.0) {
            Button {
                model.setDone(note, note.isDone == false)
            } label: {
                Image(systemName: note.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12.0))
                    .foregroundStyle(note.isDone ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(note.isDone ? "Put this back on the list" : "Done with this")

            VStack(alignment: .leading, spacing: 1.0) {
                Text(note.text)
                    .font(.system(size: 12.0))
                    .strikethrough(note.isDone)
                    .foregroundStyle(note.isDone ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let source = note.sourceDescription {
                    Text(source)
                        .font(.system(size: 10.0))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Button {
                model.delete(note)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.0))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.vertical, 3.0)
        .textSelection(.enabled)
    }
}
