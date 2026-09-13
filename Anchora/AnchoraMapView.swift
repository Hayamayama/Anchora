//
//  AnchoraMapView.swift
//  Anchora
//
//  The Paper Map navigator: pick a section, read it, and jump back into the
//  PDF from a citation or a Source quote.
//

import SwiftUI

struct AnchoraMapView: View {

    @ObservedObject var model: AnchoraMapModel
    /// Page labels for the current document, refreshed by the AppKit host.
    var pageLabels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3.0) {
            header
            if model.isExpanded {
                sectionPicker
                sourcePicker
                detail
            }
        }
        .padding(.horizontal, 8.0)
        .padding(.vertical, 6.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12.0, style: .continuous))
        .environment(\.openURL, OpenURLAction { url in
            model.handle(url: url) ? .handled : .systemAction
        })
    }

    private var header: some View {
        HStack(spacing: 8.0) {
            Text(model.title)
                .font(.system(size: 10.0, weight: .bold))
                .foregroundStyle(.secondary)
            Text(model.legend)
                .font(.system(size: 10.0))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help("Source quotes jump to, and select, their matching PDF text. Evidence labels separate direct results, author interpretation, inference, and what remains unproven.")
            Spacer(minLength: 4.0)
            Button(model.isExpanded ? "Hide" : "Show") {
                model.setExpanded(model.isExpanded == false)
            }
            .controlSize(.small)
        }
    }

    private var sectionPicker: some View {
        Picker("", selection: Binding(get: { model.selectedIndex },
                                      set: { model.selectedIndex = $0 })) {
            ForEach(Array(model.sections.enumerated()), id: \.offset) { index, section in
                Text(section.title).tag(index)
            }
        }
        .labelsHidden()
        .font(.system(size: 12.0, weight: .medium))
    }

    @ViewBuilder
    private var sourcePicker: some View {
        let pages = (model.selectedSection?.pageIndexes ?? []).map { $0.intValue }
        if pages.isEmpty {
            Text("No cited PDF page in this section")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 2.0)
        } else {
            Menu("Jump to supporting PDF page…") {
                ForEach(pages, id: \.self) { pageIndex in
                    Button("↗ PDF p. \(model.pageLabel(for: pageIndex))") {
                        model.onOpenPage?(pageIndex)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .font(.system(size: 10.5))
            .fixedSize()
        }
    }

    private var detail: some View {
        ScrollView(.vertical) {
            Group {
                if let section = model.selectedSection {
                    if model.rendersMarkdown {
                        AnchoraMarkdownText(markdown: section.text, bodySize: 12.5)
                    } else {
                        Text(model.attributedDetail(for: section, pageLabels: pageLabels))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4.0)
        }
        // A section is read inside the card; its length must never influence
        // the sidebar's own layout.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
