import Foundation
import Vision
import PDFKit
import UIKit

/// Apple Vision-backed text recognition. Renders a PDF page (or takes an image),
/// runs `VNRecognizeTextRequest` in accurate mode with language correction, and
/// returns the recognized text plus per-observation normalized bounding boxes.
enum OCREngine {

    enum OCRError: LocalizedError {
        case noImage
        case recognitionFailed(String)
        case emptyResult
        var errorDescription: String? {
            switch self {
            case .noImage: return "Could not render a page image to recognize."
            case .recognitionFailed(let m): return "Text recognition failed: \(m)."
            case .emptyResult: return "No text was found on this page."
            }
        }
    }

    /// One recognized line: its text, confidence, and Vision-normalized box
    /// (origin bottom-left, 0...1 in image space).
    struct Line {
        let text: String
        let confidence: Float
        let boundingBox: CGRect
    }

    /// Result of recognizing a single page image.
    struct PageResult {
        let text: String
        let lines: [Line]
        /// Pixel size of the image the boxes were computed against.
        let imageSize: CGSize
    }

    // MARK: - Page image rendering

    /// Render a PDF page to a CGImage at a scale suitable for OCR (2x by default
    /// so small type is legible to Vision). Uses the same flip convention as the
    /// rest of PDFEngine.
    static func renderPageImage(_ page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let pxSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: pxSize)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: pxSize))
            cg.saveGState()
            cg.translateBy(x: 0, y: pxSize.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
    }

    // MARK: - Recognition

    /// Recognize text on a single UIImage. Synchronous (Vision runs the request
    /// on the calling queue); callers should invoke from a background queue.
    static func recognize(image: UIImage) throws -> PageResult {
        guard let cg = image.cgImage else { throw OCRError.noImage }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        var lines: [Line] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            lines.append(Line(text: candidate.string,
                              confidence: candidate.confidence,
                              boundingBox: obs.boundingBox))
        }
        // Vision returns observations roughly top-to-bottom already; keep order.
        let joined = lines.map { $0.text }.joined(separator: "\n")
        let px = CGSize(width: cg.width, height: cg.height)
        guard !lines.isEmpty else { throw OCRError.emptyResult }
        return PageResult(text: joined, lines: lines, imageSize: px)
    }

    /// Recognize text across every page of a PDF, concatenated with page breaks.
    static func recognize(document: PDFDocument) throws -> String {
        var chunks: [String] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let img = renderPageImage(page) else { continue }
            if let result = try? recognize(image: img), !result.text.isEmpty {
                chunks.append("— Page \(i + 1) —\n\(result.text)")
            }
        }
        let all = chunks.joined(separator: "\n\n")
        guard !all.isEmpty else { throw OCRError.emptyResult }
        return all
    }

    // MARK: - Plain-text output file

    /// Write recognized text to a shareable .txt file.
    static func writeTextFile(_ text: String, name: String = "Extracted-Text.txt") throws -> URL {
        let url = PDFEngine.tempURL(name: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Searchable PDF (invisible text layer) — best-effort follow-up

    /// Burn an invisible (clear) freeText annotation layer over each page so the
    /// PDF becomes text-selectable. Marked in the UI as an experimental follow-up:
    /// PDFKit freeText annotations approximate glyph positions per recognized line
    /// rather than per glyph, so selection is coarse. Returns a new PDF URL.
    static func makeSearchable(_ document: PDFDocument,
                               outputName: String = "Searchable.pdf") throws -> URL {
        let out = PDFDocument()
        for i in 0..<document.pageCount {
            guard let srcPage = document.page(at: i)?.copy() as? PDFPage else { continue }
            let bounds = srcPage.bounds(for: .mediaBox)
            if let img = renderPageImage(srcPage),
               let result = try? recognize(image: img) {
                for line in result.lines {
                    // Vision box is normalized (bottom-left origin) → PDF points.
                    let bb = line.boundingBox
                    let rect = CGRect(
                        x: bounds.origin.x + bb.origin.x * bounds.width,
                        y: bounds.origin.y + bb.origin.y * bounds.height,
                        width: bb.width * bounds.width,
                        height: bb.height * bounds.height)
                    let ann = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
                    ann.contents = line.text
                    // Size the font to roughly fill the box height.
                    ann.font = UIFont.systemFont(ofSize: max(rect.height * 0.8, 6))
                    ann.fontColor = .clear     // invisible text layer
                    ann.color = .clear         // no background
                    ann.border = PDFBorder()
                    srcPage.addAnnotation(ann)
                }
            }
            out.insert(srcPage, at: out.pageCount)
        }
        guard out.pageCount > 0 else { throw OCRError.emptyResult }
        let dest = PDFEngine.tempURL(name: outputName)
        guard out.write(to: dest) else { throw OCRError.recognitionFailed("write failed") }
        return dest
    }
}
