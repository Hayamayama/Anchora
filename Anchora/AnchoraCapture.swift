//
//  AnchoraCapture.swift
//  Anchora
//
//  Turning part of a PDF into something the model can read: a rendered JPEG
//  for a figure or a whole page, and Vision text recognition for a region
//  whose own text layer is unusable.
//

import AppKit
import PDFKit
import Vision

@objc(AnchoraCapture)
public final class AnchoraCapture: NSObject {

    /// Renders at 2x so small slide type survives recognition, and never
    /// produces an impractically large request for an unusually large page.
    private static let renderScale: CGFloat = 2.0
    private static let maximumPixelsPerSide: CGFloat = 4096.0
    /// A region is inset outward slightly: a rectangle dragged tight around a
    /// line otherwise clips its ascenders and descenders.
    private static let regionBleed: CGFloat = 3.0

    /// Vision recognises only English unless it is told otherwise, so a
    /// Traditional Chinese slide came back with nothing at all.  Traditional
    /// Chinese leads because that is what these decks are written in; English
    /// stays in the list because their technical terms are not translated.
    private static let preferredLanguages = ["zh-Hant", "zh-Hans", "en-US"]

    /// Resolved once against what this machine actually supports.
    private static let recognitionLanguages: [String] = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        return AnchoraTextQuality.resolveRecognitionLanguages(preferred: preferredLanguages, supported: supported)
    }()

    // MARK: - Rendering

    /// Maps a rectangle in the page's own coordinates onto what drawing
    /// actually produces.
    ///
    /// Two things have to be undone.  `page.draw(with:to:)` places the display
    /// box's origin at the context origin, so a page point lands at
    /// `p - bounds.origin`.  And it applies the page's rotation, while
    /// `bounds(for:)` and the rectangle the view reports are both in the
    /// page's *unrotated* space -- a 90-degree page reports bounds of
    /// 600 x 800 and hands back a portrait rectangle even though it displays
    /// landscape.  Presentation decks are routinely stored this way, and
    /// without the mapping a drag lands somewhere else entirely on the slide.
    static func renderRect(for rect: NSRect, pageBounds: NSRect, rotation: Int) -> NSRect {
        let r = rect.offsetBy(dx: -pageBounds.minX, dy: -pageBounds.minY)
        let width = pageBounds.width, height = pageBounds.height
        switch ((rotation % 360) + 360) % 360 {
        case 90:
            return NSRect(x: r.minY, y: width - r.maxX, width: r.height, height: r.width)
        case 180:
            return NSRect(x: width - r.maxX, y: height - r.maxY, width: r.width, height: r.height)
        case 270:
            return NSRect(x: height - r.maxY, y: r.minX, width: r.height, height: r.width)
        default:
            return r
        }
    }

    private static func render(page: PDFPage, box: PDFDisplayBox, rect: NSRect, scale requestedScale: CGFloat) -> NSBitmapImageRep? {
        let drawRect = renderRect(for: rect, pageBounds: page.bounds(for: box), rotation: page.rotation)
        guard drawRect.isEmpty == false else { return nil }
        let scale = min(requestedScale, maximumPixelsPerSide / max(drawRect.width, drawRect.height))
        let pixelsWide = Int(ceil(drawRect.width * scale))
        let pixelsHigh = Int(ceil(drawRect.height * scale))
        guard pixelsWide > 0, pixelsHigh > 0,
              let imageRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                              pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .calibratedRGB,
                                              bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: imageRep)?.cgContext
        else { return nil }

        // A white ground matters: a PDF page draws no background of its own,
        // and dark type on transparency recognises far worse.
        context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -drawRect.minX, y: -drawRect.minY)
        page.draw(with: box, to: context)
        return imageRep
    }

    private static func dataURL(_ imageRep: NSBitmapImageRep?, compression: CGFloat) -> String? {
        guard let data = imageRep?.representation(using: .jpeg, properties: [.compressionFactor: compression]),
              data.isEmpty == false
        else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    /// A rectangular region of a page, for "here is the figure I am asking about".
    @objc public static func regionImageDataURL(page: PDFPage, box: PDFDisplayBox, rect: NSRect) -> String? {
        dataURL(render(page: page, box: box, rect: bleed(rect, on: page, box: box), scale: renderScale),
                compression: 0.82)
    }

    /// A whole page, for a visual summary that must not depend on the text layer.
    @objc public static func pageImageDataURL(page: PDFPage, box: PDFDisplayBox) -> String? {
        dataURL(render(page: page, box: box, rect: page.bounds(for: box), scale: renderScale),
                compression: 0.9)
    }

    private static func bleed(_ rect: NSRect, on page: PDFPage, box: PDFDisplayBox) -> NSRect {
        rect.insetBy(dx: -regionBleed, dy: -regionBleed).intersection(page.bounds(for: box))
    }

    // MARK: - Text recognition

    /// Recognises text in a region of a page.  `completion` runs on the main
    /// thread with the recognised text, or nil when nothing could be read.
    ///
    /// This renders the PDF content itself rather than capturing the view: a
    /// screenshot would include Skim's dimmed selection overlay, which made
    /// recognition unreliable for exactly the large slide regions this is for.
    @objc public static func recognizeText(page: PDFPage,
                                           box: PDFDisplayBox,
                                           rect: NSRect,
                                           completion: @escaping (String?) -> Void) {
        guard let image = render(page: page, box: box, rect: bleed(rect, on: page, box: box), scale: renderScale)?.cgImage else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        Task.detached(priority: .userInitiated) {
            let text = recognizeText(in: image)
            await MainActor.run { completion(text) }
        }
    }

    private static func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }

        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }.filter { $0.isEmpty == false }

        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
