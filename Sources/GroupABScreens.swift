import SwiftUI
import PDFKit
import UIKit

// MARK: - Shared building blocks (mirror ToolScreens' private helpers)

private struct GroupABScaffold<Content: View>: View {
    @Environment(\.kopi) private var kopi
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            kopi.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) { content() }
                    .padding(Space.lg)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func groupPrimaryButton(_ title: String, kopi: KopiTheme,
                                systemImage: String? = nil,
                                action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .foregroundStyle(kopi.onBrand)
    }
}

private struct ShareBar: View {
    @Environment(\.kopi) private var kopi
    let urls: [URL]
    @State private var showShare = false
    var body: some View {
        Button { showShare = true } label: {
            Label(urls.count > 1 ? "Share \(urls.count) files" : "Save & Share",
                  systemImage: "square.and.arrow.up")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(kopi.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .foregroundStyle(.white)
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: urls) }
    }
}

// MARK: - Extract Text (OCR)

struct OCRExtractView: View {
    @Environment(\.kopi) private var kopi
    @State private var doc: PDFDocument?
    @State private var sourceURL: URL?
    @State private var picking = false
    @State private var running = false
    @State private var text: String = ""
    @State private var textFile: URL?
    @State private var searchablePDF: URL?
    @State private var error: String?
    /// When true, load the sample and run OCR automatically on appear
    /// (deterministic simulator verification).
    var autorun: Bool = false

    var body: some View {
        GroupABScaffold(title: "Extract Text (OCR)") {
            if doc != nil {
                Text("Reads the text off each page with Apple Vision (on-device). Great for scans and photos of documents.")
                    .font(.body).foregroundStyle(kopi.textSoft)

                groupPrimaryButton(running ? "Recognizing…" : "Extract text",
                                   kopi: kopi, systemImage: "text.viewfinder") {
                    runOCR()
                }
                .disabled(running)

                if running { ProgressView().tint(kopi.accent) }

                if !text.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Recognized text")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.text)
                        Text(text)
                            .font(.callout).foregroundStyle(kopi.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.md)
                            .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(kopi.line))
                    }
                    if let textFile { ShareBar(urls: [textFile]) }

                    // (b) Make searchable — labelled experimental follow-up.
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Button {
                            makeSearchable()
                        } label: {
                            Label("Make PDF searchable (experimental)", systemImage: "doc.text.magnifyingglass")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
                        }
                        Text("Burns an invisible text layer so the PDF becomes selectable. Positioning is per-line, so selection is approximate — a work-in-progress.")
                            .font(.caption).foregroundStyle(kopi.textSoft)
                    }
                    if let searchablePDF { ShareBar(urls: [searchablePDF]) }
                }
            } else {
                Text("Choose a PDF, or load the sample, to pull out its text.")
                    .font(.body).foregroundStyle(kopi.textSoft)
                groupPrimaryButton("Choose a PDF", kopi: kopi) { picking = true }
                Button("Try the sample document") { loadSample() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { picked in
                if let u = picked.first { sourceURL = u; doc = PDFDocument(url: u); resetOutputs() }
            }
        }
        .onAppear {
            if autorun && doc == nil {
                loadSample()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { runOCR() }
            }
        }
    }

    private func resetOutputs() {
        text = ""; textFile = nil; searchablePDF = nil; error = nil
    }

    private func loadSample() {
        if let u = PDFEngine.makeSampleDocument(), let d = PDFDocument(url: u) {
            sourceURL = u; doc = d; resetOutputs()
        }
    }

    private func runOCR() {
        guard let doc else { return }
        running = true; error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let recognized = try OCREngine.recognize(document: doc)
                let file = try OCREngine.writeTextFile(recognized)
                DispatchQueue.main.async {
                    text = recognized; textFile = file; running = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription; running = false
                }
            }
        }
    }

    private func makeSearchable() {
        guard let doc else { return }
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try OCREngine.makeSearchable(doc)
                DispatchQueue.main.async { searchablePDF = url }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }
}

// MARK: - Scan Filters (live preview picker)

struct ScanFilterView: View {
    @Environment(\.kopi) private var kopi
    @State private var doc: PDFDocument?
    @State private var baseImage: UIImage?
    @State private var preview: UIImage?
    @State private var mode: ScanFilters.Mode = .original
    @State private var picking = false
    @State private var output: URL?
    @State private var error: String?
    // Cache of rendered previews per mode.
    @State private var cache: [ScanFilters.Mode: UIImage] = [:]
    /// Load the sample and preselect Magic Color on appear (sim verification).
    var autorun: Bool = false

    var body: some View {
        GroupABScaffold(title: "Scan Filters") {
            if let baseImage {
                Text("Clean up a scanned page: enhance, whiten the background, or go high-contrast black & white. Live preview below.")
                    .font(.body).foregroundStyle(kopi.textSoft)

                // Live preview
                Image(uiImage: preview ?? baseImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(kopi.line))

                // Filter picker — thumbnail chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.md) {
                        ForEach(ScanFilters.Mode.allCases) { m in
                            filterChip(m)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let output { ShareBar(urls: [output]) }
                groupPrimaryButton("Apply & make PDF", kopi: kopi, systemImage: "doc.badge.gearshape") {
                    applyToPDF()
                }
            } else {
                Text("Choose a PDF (its first page becomes the preview) or load the sample.")
                    .font(.body).foregroundStyle(kopi.textSoft)
                groupPrimaryButton("Choose a PDF", kopi: kopi) { picking = true }
                Button("Try the sample document") { loadSample() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { picked in
                if let u = picked.first { load(PDFDocument(url: u)) }
            }
        }
        .onAppear {
            if autorun && baseImage == nil {
                loadSample()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    mode = .magicColor
                    preview = cache[.magicColor]
                }
            }
        }
    }

    private func filterChip(_ m: ScanFilters.Mode) -> some View {
        let on = mode == m
        return VStack(spacing: 6) {
            ZStack {
                if let thumb = cache[m] {
                    Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64).clipped()
                } else {
                    Rectangle().fill(kopi.surface).frame(width: 64, height: 64)
                    Image(systemName: m.symbol).foregroundStyle(kopi.brand)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                .strokeBorder(on ? kopi.accent : kopi.line, lineWidth: on ? 2 : 1))
            Text(m.rawValue).font(.caption2.weight(on ? .bold : .medium))
                .foregroundStyle(on ? kopi.accent : kopi.textSoft)
        }
        .pressable {
            mode = m
            preview = cache[m]
        }
    }

    private func loadSample() {
        if let u = PDFEngine.makeSampleDocument() { load(PDFDocument(url: u)) }
    }

    private func load(_ d: PDFDocument?) {
        guard let d, let page = d.page(at: 0),
              let img = OCREngine.renderPageImage(page, scale: 2.0) else {
            error = "Could not render that PDF."
            return
        }
        doc = d; baseImage = img; mode = .original; output = nil; error = nil
        preview = img
        // Precompute thumbnails for each mode (small, fast).
        let small = resize(img, maxDim: 220)
        DispatchQueue.global(qos: .userInitiated).async {
            var built: [ScanFilters.Mode: UIImage] = [:]
            for m in ScanFilters.Mode.allCases {
                built[m] = ScanFilters.apply(m, to: small)
            }
            DispatchQueue.main.async { cache = built; preview = built[.original] }
        }
    }

    private func applyToPDF() {
        guard let baseImage else { return }
        do {
            let filtered = ScanFilters.apply(mode, to: baseImage)
            output = try PDFEngine.pdf(fromImages: [filtered], outputName: "Filtered-\(mode.rawValue).pdf")
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func resize(_ image: UIImage, maxDim: CGFloat) -> UIImage {
        let s = image.size
        let scale = min(maxDim / max(s.width, s.height), 1)
        let newSize = CGSize(width: s.width * scale, height: s.height * scale)
        let r = UIGraphicsImageRenderer(size: newSize)
        return r.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Convert engine screen

struct ConvertView: View {
    @Environment(\.kopi) private var kopi

    enum Job: String, CaseIterable, Identifiable {
        case imagesToPDF = "Images → PDF"
        case pdfToImages = "PDF → Images"
        case pdfToWord   = "PDF → Word"
        case pdfToExcel  = "PDF → Excel"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .imagesToPDF: return "photo.on.rectangle"
            case .pdfToImages: return "rectangle.on.rectangle"
            case .pdfToWord:   return "doc.richtext"
            case .pdfToExcel:  return "tablecells"
            }
        }
    }

    @State private var job: Job = .imagesToPDF
    @State private var pdfURL: URL?
    @State private var pdfDoc: PDFDocument?
    @State private var pickingPDF = false
    @State private var pickingImages = false
    @State private var images: [UIImage] = []
    @State private var rasterFormat: ConvertEngine.RasterFormat = .jpg
    @State private var quality: Double = 0.9
    @State private var outputs: [URL] = []
    @State private var status: String?
    @State private var excelAvailable = false
    @State private var error: String?

    var body: some View {
        GroupABScaffold(title: "Convert") {
            Text("Convert between PDF and images, and export text. Fidelity is shown honestly for each mode.")
                .font(.body).foregroundStyle(kopi.textSoft)

            // Job picker
            VStack(spacing: Space.sm) {
                ForEach(Job.allCases) { j in
                    let on = job == j
                    HStack {
                        Image(systemName: j.symbol).foregroundStyle(on ? kopi.onBrand : kopi.brand)
                            .frame(width: 28)
                        Text(j.rawValue).font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? kopi.onBrand : kopi.text)
                        Spacer()
                    }
                    .padding(Space.sm)
                    .background(on ? kopi.brand : kopi.surface,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(kopi.line))
                    .pressable { job = j; resetOutputs() }
                }
            }

            fidelityNote

            switch job {
            case .imagesToPDF: imagesToPDFBody
            default:           pdfInputBody
            }

            if !outputs.isEmpty { ShareBar(urls: outputs) }
            if let status { Text(status).font(.subheadline).foregroundStyle(kopi.accent) }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $pickingPDF) {
            DocumentPicker { picked in
                if let u = picked.first { pdfURL = u; pdfDoc = PDFDocument(url: u); resetOutputs() }
            }
        }
        .sheet(isPresented: $pickingImages) {
            ImagePicker(selectionLimit: 0) { imgs in images = imgs; resetOutputs() }
        }
    }

    @ViewBuilder private var fidelityNote: some View {
        let (msg, tone): (String, Color) = {
            switch job {
            case .imagesToPDF: return ("Lossless — each image becomes a full page.", kopi.textSoft)
            case .pdfToImages: return ("Each page is rendered to a crisp \(rasterFormat.rawValue).", kopi.textSoft)
            case .pdfToWord:   return ("Text export — layout is NOT preserved. Opens in Word/Pages as plain paragraphs.", kopi.accent)
            case .pdfToExcel:  return ("Only available when the page has clearly tabular text; otherwise it stays coming-soon (we never ship a garbage spreadsheet).", kopi.accent)
            }
        }()
        Text(msg).font(.footnote).foregroundStyle(tone)
    }

    // Images → PDF
    @ViewBuilder private var imagesToPDFBody: some View {
        if images.isEmpty {
            groupPrimaryButton("Choose images", kopi: kopi, systemImage: "photo") { pickingImages = true }
        } else {
            Text("\(images.count) image\(images.count == 1 ? "" : "s") selected.")
                .font(.subheadline).foregroundStyle(kopi.text)
            groupPrimaryButton("Make PDF", kopi: kopi, systemImage: "arrow.right.doc.on.clipboard") {
                do {
                    outputs = [try ConvertEngine.imagesToPDF(images)]
                    status = "Created a \(images.count)-page PDF."
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
            Button("Choose different images") { pickingImages = true }
                .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
        }
    }

    // PDF input jobs
    @ViewBuilder private var pdfInputBody: some View {
        if pdfDoc == nil {
            groupPrimaryButton("Choose a PDF", kopi: kopi) { pickingPDF = true }
            Button("Try the sample document") {
                if let u = PDFEngine.makeSampleDocument() { pdfURL = u; pdfDoc = PDFDocument(url: u); resetOutputs() }
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
        } else {
            Text("\(pdfDoc!.pageCount) page\(pdfDoc!.pageCount == 1 ? "" : "s") loaded.")
                .font(.subheadline).foregroundStyle(kopi.text)

            if job == .pdfToImages {
                Picker("Format", selection: $rasterFormat) {
                    ForEach(ConvertEngine.RasterFormat.allCases) { f in Text(f.rawValue).tag(f) }
                }.pickerStyle(.segmented)
                if rasterFormat == .jpg {
                    VStack(alignment: .leading) {
                        Text("Quality: \(Int(quality * 100))%").font(.subheadline.weight(.semibold)).foregroundStyle(kopi.text)
                        Slider(value: $quality, in: 0.3...1.0)
                    }
                }
                groupPrimaryButton("Export \(pdfDoc!.pageCount) \(rasterFormat.rawValue)", kopi: kopi) {
                    runPDFToImages()
                }
            } else if job == .pdfToWord {
                groupPrimaryButton("Export .docx (text)", kopi: kopi, systemImage: "doc.richtext") {
                    runPDFToWord()
                }
            } else if job == .pdfToExcel {
                groupPrimaryButton("Check for a table & export", kopi: kopi, systemImage: "tablecells") {
                    runPDFToExcel()
                }
            }
            Button("Choose a different PDF") { pickingPDF = true }
                .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
        }
    }

    private func resetOutputs() { outputs = []; status = nil; error = nil; excelAvailable = false }

    private func runPDFToImages() {
        guard let pdfURL else { return }
        do {
            outputs = try ConvertEngine.pdfToImages(pdfURL, format: rasterFormat, quality: quality)
            status = "Exported \(outputs.count) \(rasterFormat.rawValue) file\(outputs.count == 1 ? "" : "s")."
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func runPDFToWord() {
        guard let pdfURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try ConvertEngine.pdfToWord(pdfURL)
                DispatchQueue.main.async {
                    outputs = [url]; status = "Created a plain-text .docx (layout not preserved)."; error = nil
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    private func runPDFToExcel() {
        guard let pdfURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try ConvertEngine.extractText(pdfURL)
                if let rows = ConvertEngine.detectTable(in: text) {
                    let url = try ConvertEngine.rowsToExcel(rows)
                    DispatchQueue.main.async {
                        outputs = [url]
                        status = "Detected a \(rows.count)×\(rows.first?.count ?? 0) table — exported .xlsx."
                        error = nil
                    }
                } else {
                    DispatchQueue.main.async {
                        outputs = []
                        status = "No tabular text detected on this document. Excel export stays coming-soon here — a plain .xlsx of this page would be garbage. Try PDF → Word for the text."
                        error = nil
                    }
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }
}
