import AppKit
import CoreGraphics
import Foundation
import PDFKit

// A framework-level smoke test for the MVP's persistence contract. It deliberately
// uses only standard PDFKit annotation subtypes and standard metadata fields.
//
// Run:
// swiftc -framework AppKit -framework PDFKit Tools/StandardAnnotationSmokeTest.swift -o /tmp/pdf-annotation-smoke
// /tmp/pdf-annotation-smoke /tmp/pdfbuddy-standard-annotations.pdf

enum SmokeTestError: Error {
    case couldNotCreateContext
    case couldNotOpenDocument
    case missingAnnotation(String)
}

func diagnostic(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func makeOnePagePDF(at url: URL) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw SmokeTestError.couldNotCreateContext
    }
    context.beginPDFPage(nil)
    context.setFillColor(NSColor.white.cgColor)
    context.fill(mediaBox)
    context.endPDFPage()
    context.closePDF()
}

func annotation(named name: String, on page: PDFPage) -> PDFAnnotation? {
    page.annotations.first { $0.userName == name }
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/pdfbuddy-standard-annotations.pdf")
let sourceURL = outputURL.deletingLastPathComponent().appendingPathComponent("pdfbuddy-standard-annotations-source.pdf")
try makeOnePagePDF(at: sourceURL)

guard let document = PDFDocument(url: sourceURL), let page = document.page(at: 0) else {
    throw SmokeTestError.couldNotOpenDocument
}

let highlightBounds = CGRect(x: 72, y: 650, width: 300, height: 18)
// PDFAnnotationMarkup/Text are the legacy PDFKit classes that Skim itself uses.
// They remain necessary here because generic PDFAnnotation instances do not
// reliably serialize newly-created markup/text annotations on current PDFKit.
let highlight = PDFAnnotationMarkup(bounds: highlightBounds)
highlight.markupType = .highlight
highlight.quadrilateralPoints = [
    NSValue(point: CGPoint(x: 72, y: 668)),
    NSValue(point: CGPoint(x: 372, y: 668)),
    NSValue(point: CGPoint(x: 72, y: 650)),
    NSValue(point: CGPoint(x: 372, y: 650)),
]
highlight.color = NSColor.systemYellow.withAlphaComponent(0.45)
highlight.contents = "Hello world — AI explanation attached to this highlight."
highlight.userName = "PDFBuddy AI"
highlight.modificationDate = Date()
page.addAnnotation(highlight)

let note = PDFAnnotationText(bounds: CGRect(x: 400, y: 620, width: 24, height: 24))
note.contents = "Hello world — standard sticky note created by PDFBuddy AI."
note.userName = "PDFBuddy AI"
note.modificationDate = Date()
note.color = .systemYellow
page.addAnnotation(note)
diagnostic("In-memory annotations before serialization: \(page.annotations.count) (\(page.annotations.compactMap { $0.type }.joined(separator: ", ")))")

guard let serialized = document.dataRepresentation() else {
    throw SmokeTestError.missingAnnotation("PDFKit did not produce a serialized document.")
}
try serialized.write(to: outputURL)

guard let reopened = PDFDocument(url: outputURL),
      let reopenedPage = reopened.page(at: 0) else {
    throw SmokeTestError.couldNotOpenDocument
}
diagnostic("Reopened annotations: \(reopenedPage.annotations.count) (\(reopenedPage.annotations.compactMap { $0.type }.joined(separator: ", ")))")
guard let savedHighlight = annotation(named: "PDFBuddy AI", on: reopenedPage),
      reopenedPage.annotations.contains(where: { $0.type == "Highlight" }),
      reopenedPage.annotations.contains(where: { $0.type == "Text" }) else {
    throw SmokeTestError.missingAnnotation("The saved PDF did not reopen with both annotations.")
}

let annotationTypes = reopenedPage.annotations.compactMap { $0.type }.sorted().joined(separator: ", ")
guard savedHighlight.contents?.contains("Hello world") == true else {
    throw SmokeTestError.missingAnnotation("The annotation Contents field was not preserved.")
}

print("PASS: wrote and reopened standard Highlight + Text annotations (\(annotationTypes)) at \(outputURL.path)")
