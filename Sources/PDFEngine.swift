import Foundation
import PDFKit
import UIKit

/// Real PDFKit-backed operations. No stubs — every method produces a real file.
enum PDFEngine {

    enum EngineError: LocalizedError {
        case cannotOpen(URL)
        case emptyResult
        case writeFailed(URL)
        var errorDescription: String? {
            switch self {
            case .cannotOpen(let u): return "Could not open PDF at \(u.lastPathComponent)."
            case .emptyResult: return "The operation produced no pages."
            case .writeFailed(let u): return "Could not write \(u.lastPathComponent)."
            }
        }
    }

    /// Temp output URL with a friendly name.
    static func tempURL(name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(name)
    }

    // MARK: - Merge

    /// Combine several PDFs (in order) into one document.
    static func merge(_ urls: [URL], outputName: String = "Merged.pdf") throws -> URL {
        let out = PDFDocument()
        var pageIndex = 0
        for url in urls {
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            guard let doc = PDFDocument(url: url) else { throw EngineError.cannotOpen(url) }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i)?.copy() as? PDFPage {
                    out.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            }
        }
        guard out.pageCount > 0 else { throw EngineError.emptyResult }
        let dest = tempURL(name: outputName)
        guard out.write(to: dest) else { throw EngineError.writeFailed(dest) }
        return dest
    }

    // MARK: - Split

    /// Split into one file per contiguous range. Ranges are 0-based inclusive.
    static func split(_ url: URL, ranges: [ClosedRange<Int>]) throws -> [URL] {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { throw EngineError.cannotOpen(url) }
        var results: [URL] = []
        for (idx, range) in ranges.enumerated() {
            let part = PDFDocument()
            var dst = 0
            for p in range {
                guard p >= 0, p < doc.pageCount else { continue }
                if let page = doc.page(at: p)?.copy() as? PDFPage {
                    part.insert(page, at: dst); dst += 1
                }
            }
            guard part.pageCount > 0 else { continue }
            let dest = tempURL(name: "Split-\(idx + 1).pdf")
            guard part.write(to: dest) else { throw EngineError.writeFailed(dest) }
            results.append(dest)
        }
        guard !results.isEmpty else { throw EngineError.emptyResult }
        return results
    }

    // MARK: - Extract

    /// Pull a specific set of pages (0-based) into a single new PDF, preserving order.
    static func extract(_ url: URL, pages: [Int], outputName: String = "Extracted.pdf") throws -> URL {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { throw EngineError.cannotOpen(url) }
        let out = PDFDocument()
        var dst = 0
        for p in pages where p >= 0 && p < doc.pageCount {
            if let page = doc.page(at: p)?.copy() as? PDFPage {
                out.insert(page, at: dst); dst += 1
            }
        }
        guard out.pageCount > 0 else { throw EngineError.emptyResult }
        let dest = tempURL(name: outputName)
        guard out.write(to: dest) else { throw EngineError.writeFailed(dest) }
        return dest
    }

    // MARK: - Compress

    /// Re-render each page to a JPEG-backed image at a scale/quality, rebuilding
    /// a smaller flattened PDF. Loses selectable text, but genuinely shrinks
    /// image-heavy scans. Returns (url, originalBytes, newBytes).
    static func compress(_ url: URL, scale: CGFloat = 1.0, jpegQuality: CGFloat = 0.5,
                         outputName: String = "Compressed.pdf") throws -> (url: URL, original: Int, compressed: Int) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { throw EngineError.cannotOpen(url) }
        let originalBytes = (try? Data(contentsOf: url).count) ?? 0

        let out = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pxSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: pxSize)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: pxSize))
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: pxSize.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
            guard let jpeg = image.jpegData(compressionQuality: jpegQuality),
                  let jpegImage = UIImage(data: jpeg),
                  let newPage = PDFPage(image: jpegImage) else { continue }
            // Keep original point size so the page isn't physically resized.
            newPage.setBounds(bounds, for: .mediaBox)
            out.insert(newPage, at: out.pageCount)
        }
        guard out.pageCount > 0 else { throw EngineError.emptyResult }
        let dest = tempURL(name: outputName)
        guard out.write(to: dest) else { throw EngineError.writeFailed(dest) }
        let newBytes = (try? Data(contentsOf: dest).count) ?? 0
        return (dest, originalBytes, newBytes)
    }

    // MARK: - Redact (TRUE removal via rasterize/flatten)

    /// Paint opaque boxes over regions, then flatten the whole page to an image so
    /// the underlying text/vector content is physically gone (not selectable).
    /// `regions` maps a 0-based page index to rectangles in PDF page coordinates
    /// (origin bottom-left, points).
    static func redact(_ url: URL, regions: [Int: [CGRect]],
                       outputName: String = "Redacted.pdf") throws -> URL {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { throw EngineError.cannotOpen(url) }
        let out = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: bounds.size)
            let image = renderer.image { ctx in
                let cg = ctx.cgContext
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: bounds.size))
                // Draw the PDF page (flip to UIKit top-left space).
                cg.saveGState()
                cg.translateBy(x: 0, y: bounds.height)
                cg.scaleBy(x: 1, y: -1)
                cg.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
                // Paint opaque redaction boxes (convert PDF coords -> UIKit coords).
                UIColor.black.setFill()
                for rect in regions[i] ?? [] {
                    let flipped = CGRect(
                        x: rect.origin.x - bounds.origin.x,
                        y: bounds.height - (rect.origin.y - bounds.origin.y) - rect.height,
                        width: rect.width, height: rect.height)
                    ctx.fill(flipped)
                }
            }
            guard let newPage = PDFPage(image: image) else { continue }
            newPage.setBounds(bounds, for: .mediaBox)
            out.insert(newPage, at: out.pageCount)
        }
        guard out.pageCount > 0 else { throw EngineError.emptyResult }
        let dest = tempURL(name: outputName)
        guard out.write(to: dest) else { throw EngineError.writeFailed(dest) }
        return dest
    }

    // MARK: - Images → PDF (document scanning)

    /// Build a multi-page PDF from captured page images, one PDF page per image.
    /// Each page is sized to its image so no scaling artefacts appear.
    static func pdf(fromImages images: [UIImage], outputName: String = "Scan.pdf") throws -> URL {
        guard !images.isEmpty else { throw EngineError.emptyResult }
        let out = PDFDocument()
        for image in images {
            guard let page = PDFPage(image: image) else { continue }
            out.insert(page, at: out.pageCount)
        }
        guard out.pageCount > 0 else { throw EngineError.emptyResult }
        let dest = tempURL(name: outputName)
        guard out.write(to: dest) else { throw EngineError.writeFailed(dest) }
        return dest
    }

    /// Place several images STACKED vertically on a SINGLE US-Letter PDF page —
    /// used for an ID card (front + back on one page). Images are laid out top to
    /// bottom, each scaled to fit the page width, evenly spaced.
    static func stackedPDF(fromImages images: [UIImage], outputName: String = "ID-Card.pdf") throws -> URL {
        guard !images.isEmpty else { throw EngineError.emptyResult }
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter pts
        let margin: CGFloat = 36
        let gap: CGFloat = 24
        let contentWidth = pageRect.width - margin * 2

        // Compute each image's drawn height at the fixed content width, then a
        // uniform vertical scale so the whole stack fits within the page height.
        let drawnHeights: [CGFloat] = images.map { img in
            guard img.size.width > 0 else { return 0 }
            return contentWidth * (img.size.height / img.size.width)
        }
        let totalGap = gap * CGFloat(max(images.count - 1, 0))
        let available = pageRect.height - margin * 2 - totalGap
        let naturalTotal = drawnHeights.reduce(0, +)
        let fitScale = naturalTotal > available && naturalTotal > 0 ? available / naturalTotal : 1.0

        let dest = tempURL(name: outputName)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        do {
            try renderer.writePDF(to: dest) { ctx in
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.cgContext.fill(pageRect)
                var y = margin
                for (idx, img) in images.enumerated() {
                    let h = drawnHeights[idx] * fitScale
                    let rect = CGRect(x: margin, y: y, width: contentWidth, height: h)
                    img.draw(in: rect)
                    y += h + gap
                }
            }
        } catch {
            throw EngineError.writeFailed(dest)
        }
        return dest
    }

    // MARK: - Save annotated document

    /// Persist an in-memory (annotated) PDFDocument to a temp file for sharing.
    static func save(_ document: PDFDocument, outputName: String = "Edited.pdf") throws -> URL {
        guard document.pageCount > 0 else { throw EngineError.emptyResult }
        let dest = tempURL(name: outputName)
        guard document.write(to: dest) else { throw EngineError.writeFailed(dest) }
        return dest
    }

    // MARK: - Sample document generator (so the editor is demoable on a fresh sim)

    /// Build a small multi-page sample PDF with real text, for demoing the editor.
    static func makeSampleDocument(outputName: String = "Kopitiam-Sample.pdf") -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter pts
        let dest = tempURL(name: outputName)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 28),
            .foregroundColor: UIColor(red: 0.435, green: 0.306, blue: 0.216, alpha: 1)
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor(red: 0.10, green: 0.075, blue: 0.063, alpha: 1)
        ]
        do {
            try renderer.writePDF(to: dest) { context in
                for pageNo in 1...3 {
                    context.beginPage()
                    ("Kopitiam Sample — Page \(pageNo)" as NSString)
                        .draw(at: CGPoint(x: 48, y: 64), withAttributes: titleAttrs)
                    let body = """
                    This is a real, selectable PDF page generated on-device so you can \
                    try the editor immediately. Tap "Text" then tap the page to place \
                    editable text. Tap "Draw" to ink with your finger. Tap "Highlight" \
                    to mark a region. Then Save & Share the result.

                    Sensitive line to try Redact on: Account 4111-1111-1111-1111.
                    """
                    (body as NSString).draw(
                        in: CGRect(x: 48, y: 120, width: 516, height: 560),
                        withAttributes: bodyAttrs)
                }
            }
            return dest
        } catch {
            return nil
        }
    }
}
