import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Group B "Convert" operations. Every method produces a real file on disk.
/// Fidelity is deliberately honest: image↔PDF and PDF→images are lossless-ish
/// raster operations; PDF→Word is a plain-text WordprocessingML document
/// (layout NOT preserved); PDF→Excel is offered only when tabular text is
/// detected, otherwise the caller marks it coming-soon.
enum ConvertEngine {

    enum ConvertError: LocalizedError {
        case cannotOpen(URL)
        case emptyResult
        case writeFailed(URL)
        case noText
        var errorDescription: String? {
            switch self {
            case .cannotOpen(let u): return "Could not open \(u.lastPathComponent)."
            case .emptyResult: return "The conversion produced nothing."
            case .writeFailed(let u): return "Could not write \(u.lastPathComponent)."
            case .noText: return "No extractable text was found."
            }
        }
    }

    enum RasterFormat: String, CaseIterable, Identifiable {
        case jpg = "JPG"
        case png = "PNG"
        var id: String { rawValue }
        var ext: String { self == .jpg ? "jpg" : "png" }
    }

    // MARK: - image → PDF

    /// One PDF page per image, each page sized to its image. Reuses PDFEngine.
    static func imagesToPDF(_ images: [UIImage], outputName: String = "Converted.pdf") throws -> URL {
        try PDFEngine.pdf(fromImages: images, outputName: outputName)
    }

    // MARK: - PDF → images

    /// Render each page to a JPG or PNG at the given scale/quality. Returns one
    /// file per page.
    static func pdfToImages(_ url: URL, format: RasterFormat, quality: CGFloat = 0.9,
                            scale: CGFloat = 2.0) throws -> [URL] {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { throw ConvertError.cannotOpen(url) }
        var results: [URL] = []
        let base = url.deletingPathExtension().lastPathComponent
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pxSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: pxSize)
            let image = renderer.image { ctx in
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
            let data: Data?
            switch format {
            case .jpg: data = image.jpegData(compressionQuality: quality)
            case .png: data = image.pngData()
            }
            guard let d = data else { continue }
            let dest = PDFEngine.tempURL(name: "\(base)-\(i + 1).\(format.ext)")
            do { try d.write(to: dest); results.append(dest) }
            catch { throw ConvertError.writeFailed(dest) }
        }
        guard !results.isEmpty else { throw ConvertError.emptyResult }
        return results
    }

    /// Render a single UIImage to a shareable JPG/PNG file (Export to JPG/PNG).
    static func imageToFile(_ image: UIImage, format: RasterFormat, quality: CGFloat = 0.9,
                            name: String = "Export") throws -> URL {
        let data: Data?
        switch format {
        case .jpg: data = image.jpegData(compressionQuality: quality)
        case .png: data = image.pngData()
        }
        guard let d = data else { throw ConvertError.emptyResult }
        let dest = PDFEngine.tempURL(name: "\(name).\(format.ext)")
        do { try d.write(to: dest); return dest }
        catch { throw ConvertError.writeFailed(dest) }
    }

    // MARK: - Text extraction (PDFKit first, OCR fallback)

    /// Pull text from a PDF. Prefer the embedded text layer (PDFKit `string`);
    /// if the document is a scan with no text layer, fall back to Vision OCR.
    static func extractText(_ url: URL) throws -> String {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: url) else { throw ConvertError.cannotOpen(url) }
        if let embedded = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !embedded.isEmpty {
            return embedded
        }
        // Scanned PDF — OCR every page.
        if let ocr = try? OCREngine.recognize(document: doc), !ocr.isEmpty {
            return ocr
        }
        throw ConvertError.noText
    }

    // MARK: - PDF → Word (.docx, plain text, honest fidelity)

    /// Build a minimal but valid .docx (Office Open XML) whose body is the
    /// extracted plain text, one paragraph per line. Layout is NOT preserved —
    /// this is an honest text export the UI labels as such. A .docx is a ZIP of
    /// XML parts; we assemble the minimum Word will open.
    static func pdfToWord(_ url: URL, outputName: String = "Converted.docx") throws -> URL {
        let text = try extractText(url)
        let dest = PDFEngine.tempURL(name: outputName)
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { paragraphXML($0) }
            .joined()

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(paragraphs)<w:sectPr/></w:body></w:document>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        try ZipWriter.write(dest, entries: [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("word/document.xml", Data(documentXML.utf8)),
        ])
        return dest
    }

    private static func paragraphXML(_ line: String) -> String {
        let escaped = xmlEscape(line)
        // xml:space=preserve keeps blank lines as visible empty paragraphs.
        return "<w:p><w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
    }

    // MARK: - Tabular detection + PDF → Excel (.xlsx)

    /// Heuristic: does the extracted text look tabular? We treat 2+ lines that
    /// each split into the SAME count (>= 2) of whitespace/tab-separated columns
    /// as a table. Returns the parsed rows when tabular, else nil.
    static func detectTable(in text: String) -> [[String]]? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }

        // Split on tabs, or runs of 2+ spaces (column gutters).
        func cols(_ s: String) -> [String] {
            if s.contains("\t") {
                return s.components(separatedBy: "\t")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            return s.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        let rows = lines.map { cols($0) }
        let counts = rows.map { $0.count }
        // Consider it a table only if a clear majority of rows share the same
        // column count and that count is >= 2.
        guard let modal = counts.sorted().middleMode, modal >= 2 else { return nil }
        let matching = counts.filter { $0 == modal }.count
        guard matching >= 2, Double(matching) / Double(counts.count) >= 0.6 else { return nil }
        // Normalize every row to the modal width.
        let normalized = rows.map { row -> [String] in
            var r = row
            while r.count < modal { r.append("") }
            if r.count > modal { r = Array(r.prefix(modal)) }
            return r
        }
        return normalized
    }

    /// Build a minimal .xlsx from parsed rows. Only call when detectTable != nil.
    static func rowsToExcel(_ rows: [[String]], outputName: String = "Converted.xlsx") throws -> URL {
        guard !rows.isEmpty else { throw ConvertError.emptyResult }
        let dest = PDFEngine.tempURL(name: outputName)

        var sheetRows = ""
        for (r, row) in rows.enumerated() {
            var cells = ""
            for (c, value) in row.enumerated() {
                let ref = "\(columnLetter(c))\(r + 1)"
                cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(value))</t></is></c>"
            }
            sheetRows += "<row r=\"\(r + 1)\">\(cells)</row>"
        }
        let sheetXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(sheetRows)</sheetData></worksheet>
        """
        let workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try ZipWriter.write(dest, entries: [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheetXML.utf8)),
        ])
        return dest
    }

    // MARK: - Helpers

    private static func columnLetter(_ index: Int) -> String {
        var i = index
        var s = ""
        repeat {
            s = String(UnicodeScalar(65 + (i % 26))!) + s
            i = i / 26 - 1
        } while i >= 0
        return s
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private extension Array where Element == Int {
    /// Modal value (most frequent); ties resolve to the middle-ish value.
    var middleMode: Int? {
        guard !isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for v in self { counts[v, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 0
        let candidates = counts.filter { $0.value == maxCount }.keys.sorted()
        return candidates.isEmpty ? nil : candidates[candidates.count / 2]
    }
}
