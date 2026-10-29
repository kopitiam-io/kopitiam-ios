import SwiftUI
import VisionKit
import Vision
import AVFoundation
import PDFKit
import UIKit

// MARK: - VisionKit document camera wrapper

/// Wraps `VNDocumentCameraViewController` (the system edge-detection scanner)
/// in a SwiftUI-presentable controller. Returns the captured page images (in
/// order) on finish, an empty array on cancel, and surfaces failures as an
/// error string.
struct DocumentScanner: UIViewControllerRepresentable {
    let onComplete: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel, onError: onError)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: ([UIImage]) -> Void
        let onCancel: () -> Void
        let onError: (String) -> Void

        init(onComplete: @escaping ([UIImage]) -> Void,
             onCancel: @escaping () -> Void,
             onError: @escaping (String) -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
            controller.dismiss(animated: true) { self.onComplete(images) }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { self.onCancel() }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true) { self.onError(error.localizedDescription) }
        }
    }
}

// MARK: - Themed unsupported state (simulator / no-camera devices)

/// Shown when `VNDocumentCameraViewController.isSupported` is false (e.g. the
/// iOS Simulator has no camera). Keeps the warm-kopi look and never crashes.
struct ScannerUnsupportedState: View {
    @Environment(\.kopi) private var kopi
    let symbol: String
    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(kopi.brand)
            Text("Scanning needs a camera")
                .font(.title2.weight(.bold))
                .foregroundStyle(kopi.text)
                .multilineTextAlignment(.center)
            Text("Open Kopitiam on an iPhone or iPad with a camera to scan documents into PDFs. The Simulator has no camera, so scanning is disabled here.")
                .font(.body)
                .foregroundStyle(kopi.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.lg)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Space.xl)
        .padding(Space.lg)
        .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(kopi.line))
    }
}

// MARK: - Scan flow model

/// How captured page images are assembled into the final PDF.
enum ScanLayout {
    /// One PDF page per captured image (document + batch).
    case onePagePerImage
    /// Front/back stacked onto a single PDF page (id-card).
    case stackedOnOnePage
}

// MARK: - Shared scan tool screen

/// A reusable scan screen: shows an intro + primary "Start scanning" button when
/// supported, presents the system camera on tap, converts the returned images to
/// a PDF via PDFEngine, and offers Save & Share. On the Simulator (or any device
/// without a camera) it shows a themed unsupported state instead.
struct ScanToolView: View {
    @Environment(\.kopi) private var kopi
    let title: String
    let intro: String
    let symbol: String
    let layout: ScanLayout
    let outputName: String

    @State private var scanning = false
    @State private var output: URL?
    @State private var pageCount = 0
    @State private var error: String?

    private var supported: Bool { VNDocumentCameraViewController.isSupported }

    var body: some View {
        ZStack {
            kopi.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text(intro)
                        .font(.body)
                        .foregroundStyle(kopi.textSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    if supported {
                        heroCard
                        Button { scanning = true } label: {
                            Label(output == nil ? "Start scanning" : "Scan again",
                                  systemImage: "camera.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .foregroundStyle(kopi.onBrand)
                        }
                        if let output {
                            Text("Captured \(pageCount) page\(pageCount == 1 ? "" : "s") → one PDF.")
                                .font(.subheadline)
                                .foregroundStyle(kopi.accent)
                            ScanResultActions(url: output)
                        }
                    } else {
                        ScannerUnsupportedState(symbol: symbol)
                    }

                    if let error {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
                .padding(Space.lg)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner(
                onComplete: { images in
                    scanning = false
                    buildPDF(from: images)
                },
                onCancel: { scanning = false },
                onError: { msg in scanning = false; error = msg }
            )
            .ignoresSafeArea()
        }
    }

    private var heroCard: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(kopi.brand)
            Text("Point the camera at your document — Kopitiam finds the edges and straightens each page automatically.")
                .font(.subheadline)
                .foregroundStyle(kopi.textSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.lg)
        .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(kopi.line))
    }

    private func buildPDF(from images: [UIImage]) {
        guard !images.isEmpty else { return }
        do {
            switch layout {
            case .onePagePerImage:
                output = try PDFEngine.pdf(fromImages: images, outputName: outputName)
                pageCount = images.count
            case .stackedOnOnePage:
                // Real card size, not stretched to the page width.
                output = try IDCardPDF.make(images: images, layout: .onePage,
                                            paper: PaperSize.regionDefault, outputName: outputName)
                pageCount = 1
            }
            // Keep a copy on the phone so it shows in Recents and Files.
            if let made = output {
                let prefix = layout == .stackedOnOnePage ? "ID Card" : "Scan"
                output = (try? DocumentStore.shared.save(made, title: DocumentStore.title(prefix)))?.url ?? made
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Result actions (mirrors ToolScreens' private ResultActions)

private struct ScanResultActions: View {
    @Environment(\.kopi) private var kopi
    let url: URL
    @State private var showShare = false
    var body: some View {
        Button { showShare = true } label: {
            Label("Save & Share", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .foregroundStyle(kopi.onBrand)
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: [url]) }
    }
}

// MARK: - Concrete scan screens

struct ScanDocumentView: View {
    var body: some View {
        ScanToolView(
            title: "Scan Document",
            intro: "Scan a page straight into a PDF. Capture as many pages as you like — each becomes a page in one document.",
            symbol: "doc.viewfinder",
            layout: .onePagePerImage,
            outputName: "Scan.pdf")
    }
}

struct ScanIDCardView: View {
    var body: some View {
        ScanToolView(
            title: "Scan ID Card",
            intro: "Scan the FRONT of the ID first, then the BACK. Both sides are placed stacked on a single PDF page — ideal for a passport, driver’s licence, or membership card.",
            symbol: "person.text.rectangle",
            layout: .stackedOnOnePage,
            outputName: "ID-Card.pdf")
    }
}

struct ScanBatchView: View {
    var body: some View {
        ScanToolView(
            title: "Batch Scan",
            intro: "Scan many pages in one session — receipts, a contract, a stack of forms. Every captured page lands in a single PDF, in order.",
            symbol: "square.stack.3d.up",
            layout: .onePagePerImage,
            outputName: "Batch-Scan.pdf")
    }
}

// MARK: - Saved documents (Recents + Files)
//
// Scans are kept in Application Support/Documents inside the app. They never
// leave the phone (beyond the user's own device backup) and are listed newest
// first on Home (Recents) and in the Files tab.

struct SavedDocument: Identifiable, Hashable {
    let url: URL
    let name: String
    let modified: Date
    let pageCount: Int
    var id: String { url.lastPathComponent }
}

/// Used from the main thread only (views and their actions).
final class DocumentStore: ObservableObject {
    static let shared = DocumentStore()

    @Published private(set) var documents: [SavedDocument] = []
    let folder: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        documents = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let pages = CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
                return SavedDocument(url: url, name: url.deletingPathExtension().lastPathComponent,
                                     modified: date, pageCount: pages)
            }
            .sorted { $0.modified > $1.modified }
    }

    func document(id: String) -> SavedDocument? {
        documents.first { $0.id == id }
    }

    /// Copy a freshly made PDF into the store under a unique, readable name.
    @discardableResult
    func save(_ source: URL, title: String) throws -> SavedDocument {
        let dest = uniqueURL(for: title)
        try FileManager.default.copyItem(at: source, to: dest)
        reload()
        return document(id: dest.lastPathComponent)
            ?? SavedDocument(url: dest, name: dest.deletingPathExtension().lastPathComponent,
                             modified: Date(), pageCount: 0)
    }

    func delete(_ doc: SavedDocument) {
        try? FileManager.default.removeItem(at: doc.url)
        reload()
    }

    /// Returns the renamed document, or nil if the name was empty or the move failed.
    @discardableResult
    func rename(_ doc: SavedDocument, to newName: String) -> SavedDocument? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != doc.name else { return doc }
        let dest = uniqueURL(for: trimmed)
        do {
            try FileManager.default.moveItem(at: doc.url, to: dest)
        } catch {
            return nil
        }
        reload()
        return document(id: dest.lastPathComponent)
    }

    private func uniqueURL(for title: String) -> URL {
        let base = Self.safeName(title)
        var dest = folder.appendingPathComponent(base).appendingPathExtension("pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(base) (\(n))").appendingPathExtension("pdf")
            n += 1
        }
        return dest
    }

    static func safeName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Document" : String(cleaned.prefix(80))
    }

    /// "Scan 29 Oct 2026, 19.06" — dots, not colons, so it is a valid file name.
    static func title(_ prefix: String, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM yyyy, HH.mm"
        return "\(prefix) \(f.string(from: date))"
    }

    /// Launch argument `-seedSamples` fills an empty store with two sample
    /// documents, for screenshots on a simulator that has no camera.
    func seedSamplesIfRequested() {
        guard CommandLine.arguments.contains("-seedSamples"), documents.isEmpty else { return }
        if let sample = PDFEngine.makeSampleDocument() {
            try? save(sample, title: "Lease agreement")
        }
        if let id = try? IDCardPDF.make(images: IDCardPDF.sampleCards(), layout: .onePage, paper: .a4) {
            try? save(id, title: Self.title("ID Card"))
        }
    }
}

/// First-page thumbnail, rendered off the main thread.
struct PDFThumbnail: View {
    @Environment(\.kopi) private var kopi
    let url: URL
    var size = CGSize(width: 44, height: 56)
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(kopi.line))
        .accessibilityHidden(true)
        .task(id: url) {
            let target = CGSize(width: size.width * 3, height: size.height * 3)
            let u = url
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let page = PDFDocument(url: u)?.page(at: 0) else { return nil }
                return page.thumbnail(of: target, for: .mediaBox)
            }.value
        }
    }
}

/// One saved document in a list: thumbnail, name, date and page count.
struct DocumentRow: View {
    @Environment(\.kopi) private var kopi
    let doc: SavedDocument

    var body: some View {
        HStack(spacing: Space.md) {
            PDFThumbnail(url: doc.url)
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(kopi.text)
                    .lineLimit(1)
                Text("\(doc.modified.formatted(date: .abbreviated, time: .shortened)) · \(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(kopi.textSoft)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(kopi.textSoft)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Read-only PDF view for a saved document.
struct SavedPDFView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

/// A saved document: view it, share it, rename or delete it.
struct DocumentDetailView: View {
    @Environment(\.kopi) private var kopi
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DocumentStore.shared
    @State private var docID: String
    @State private var showShare = false
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameFailed = false

    init(documentID: String) { _docID = State(initialValue: documentID) }

    private var doc: SavedDocument? { store.document(id: docID) }

    var body: some View {
        Group {
            if let doc {
                SavedPDFView(url: doc.url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Text("This document is no longer on this phone.")
                    .foregroundStyle(kopi.textSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(kopi.bg)
            }
        }
        .navigationTitle(doc?.name ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if doc != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            newName = doc?.name ?? ""
                            renaming = true
                        } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let doc { ShareSheet(items: [doc.url]) }
        }
        .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let doc { store.delete(doc) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from this phone. This can't be undone.")
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let doc {
                    if let renamed = store.rename(doc, to: newName) {
                        docID = renamed.id
                    } else {
                        renameFailed = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't rename this document.", isPresented: $renameFailed) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - ID card PDF (real size)

enum IDPageLayout: String, CaseIterable, Identifiable {
    case onePage, separatePages
    var id: String { rawValue }
    var title: String { self == .onePage ? "One page" : "Separate pages" }
    var subtitle: String { self == .onePage ? "For photocopies" : "For uploads" }
}

enum PaperSize: String, CaseIterable, Identifiable {
    case a4, letter
    var id: String { rawValue }
    var title: String { self == .a4 ? "A4" : "US Letter" }
    /// Points (1/72 inch).
    var size: CGSize {
        self == .a4 ? CGSize(width: 595.28, height: 841.89) : CGSize(width: 612, height: 792)
    }
    /// Letter in the US and Canada, A4 everywhere else.
    static var regionDefault: PaperSize {
        let region = Locale.current.region?.identifier ?? ""
        return ["US", "CA", "MX", "PH"].contains(region) ? .letter : .a4
    }
}

enum IDCardPDF {
    /// ISO/IEC 7810 ID-1 (ID cards, licences, bank cards): 85.6 x 54 mm.
    static let cardSize = CGSize(width: 85.6 / 25.4 * 72, height: 54.0 / 25.4 * 72)
    static let cardRatio: CGFloat = 85.6 / 54.0

    /// True when an image has the ID-1 shape (either orientation), within 8%.
    static func looksLikeCard(_ image: UIImage) -> Bool {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return false }
        let ratio = max(w, h) / min(w, h)
        return abs(ratio - cardRatio) / cardRatio < 0.08
    }

    /// Cards print landscape; rotate portrait captures a quarter turn.
    static func landscape(_ image: UIImage) -> UIImage {
        guard image.size.height > image.size.width else { return image }
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: -.pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
        }
    }

    /// Front (and back) at the card's true printed size, centred horizontally.
    static func make(images: [UIImage], layout: IDPageLayout, paper: PaperSize,
                     outputName: String = "ID-Card.pdf") throws -> URL {
        guard !images.isEmpty else { throw PDFEngine.EngineError.emptyResult }
        let cards = images.map(landscape)
        let page = CGRect(origin: .zero, size: paper.size)
        let topMargin: CGFloat = 72
        let gap: CGFloat = 36
        let dest = PDFEngine.tempURL(name: outputName)

        func draw(_ image: UIImage, top: CGFloat) {
            let slot = CGRect(x: (page.width - cardSize.width) / 2, y: top,
                              width: cardSize.width, height: cardSize.height)
            // Aspect-fit inside the card slot so a slightly off crop never stretches.
            let scale = min(slot.width / image.size.width, slot.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: slot.midX - w / 2, y: slot.midY - h / 2, width: w, height: h))
        }

        do {
            try UIGraphicsPDFRenderer(bounds: page).writePDF(to: dest) { ctx in
                switch layout {
                case .onePage:
                    ctx.beginPage()
                    var y = topMargin
                    for card in cards {
                        draw(card, top: y)
                        y += cardSize.height + gap
                    }
                case .separatePages:
                    for card in cards {
                        ctx.beginPage()
                        draw(card, top: topMargin)
                    }
                }
            }
        } catch {
            throw PDFEngine.EngineError.writeFailed(dest)
        }
        return dest
    }

    /// Drawn placeholder cards for screenshots on a simulator with no camera.
    static func sampleCards() -> [UIImage] {
        let size = CGSize(width: 856, height: 540)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        func card(_ top: UIColor, _ bottom: UIColor, back: Bool) -> UIImage {
            renderer.image { ctx in
                let cg = ctx.cgContext
                let colors = [top.cgColor, bottom.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
                let ink = UIColor(white: 0.1, alpha: 0.28)
                if back {
                    ink.setFill()
                    for i in 0..<34 {
                        let w: CGFloat = i % 3 == 0 ? 8 : 4
                        cg.fill(CGRect(x: 60 + CGFloat(i) * 21, y: 380, width: w, height: 90))
                    }
                    cg.fill(CGRect(x: 60, y: 80, width: 520, height: 22))
                    cg.fill(CGRect(x: 60, y: 130, width: 380, height: 22))
                } else {
                    UIColor(white: 1, alpha: 0.6).setFill()
                    cg.fill(CGRect(x: 60, y: 130, width: 210, height: 270))
                    ink.setFill()
                    cg.fill(CGRect(x: 320, y: 150, width: 420, height: 26))
                    cg.fill(CGRect(x: 320, y: 210, width: 300, height: 22))
                    cg.fill(CGRect(x: 320, y: 260, width: 340, height: 22))
                    let label: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 34),
                        .foregroundColor: UIColor(white: 0.1, alpha: 0.6),
                    ]
                    ("SAMPLE IDENTITY CARD" as NSString).draw(at: CGPoint(x: 60, y: 50), withAttributes: label)
                }
            }
        }
        return [
            card(UIColor(red: 0.81, green: 0.89, blue: 0.86, alpha: 1),
                 UIColor(red: 0.56, green: 0.74, blue: 0.68, alpha: 1), back: false),
            card(UIColor(red: 0.91, green: 0.86, blue: 0.78, alpha: 1),
                 UIColor(red: 0.78, green: 0.69, blue: 0.54, alpha: 1), back: true),
        ]
    }
}

// MARK: - ID layout choice (after capture)

/// Pick how the card prints, looking at a preview of each layout.
struct IDLayoutView: View {
    @Environment(\.kopi) private var kopi
    let images: [UIImage]
    let onSaved: (SavedDocument) -> Void
    var onRetake: (() -> Void)?

    @AppStorage("idLayout") private var layoutRaw = IDPageLayout.onePage.rawValue
    @AppStorage("paperSize") private var paperRaw = PaperSize.regionDefault.rawValue
    @State private var error: String?
    @State private var saving = false

    private var layout: IDPageLayout { IDPageLayout(rawValue: layoutRaw) ?? .onePage }
    private var paper: PaperSize { PaperSize(rawValue: paperRaw) ?? .a4 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("How should it print?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(kopi.text)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: Space.md) {
                    ForEach(IDPageLayout.allCases) { option in
                        layoutOption(option)
                    }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Paper")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(kopi.textSoft)
                    Picker("Paper", selection: $paperRaw) {
                        ForEach(PaperSize.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Label("Printed at the card's real size, 85.6 × 54 mm.", systemImage: "ruler")
                    .font(.footnote)
                    .foregroundStyle(kopi.textSoft)

                Button(action: save) {
                    Text(saving ? "Saving…" : "Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .foregroundStyle(kopi.onBrand)
                }
                .disabled(saving)

                if let onRetake {
                    Button("Scan again", action: onRetake)
                        .font(.headline)
                        .foregroundStyle(kopi.accent)
                        .frame(maxWidth: .infinity)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(Space.lg)
        }
        .background(kopi.bg.ignoresSafeArea())
        .navigationTitle("ID Card")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func layoutOption(_ option: IDPageLayout) -> some View {
        let selected = option == layout
        return Button { layoutRaw = option.rawValue } label: {
            VStack(spacing: Space.sm) {
                IDPagePreview(images: images, layout: option, paper: paper)
                    .frame(height: 170)
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kopi.text)
                Text(option.subtitle)
                    .font(.caption)
                    .foregroundStyle(kopi.textSoft)
            }
            .padding(Space.sm)
            .frame(maxWidth: .infinity)
            .background(selected ? kopi.accent.opacity(0.12) : kopi.surface,
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(selected ? kopi.accent : kopi.line, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title), \(option.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        saving = true
        defer { saving = false }
        do {
            let url = try IDCardPDF.make(images: images, layout: layout, paper: paper)
            let doc = try DocumentStore.shared.save(url, title: DocumentStore.title("ID Card"))
            error = nil
            onSaved(doc)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Miniature of the printed page(s), drawn to the same proportions as the PDF.
struct IDPagePreview: View {
    let images: [UIImage]
    let layout: IDPageLayout
    let paper: PaperSize

    var body: some View {
        GeometryReader { geo in
            let pages = layout == .onePage ? [images] : images.map { [$0] }
            let gap: CGFloat = 6
            let count = CGFloat(max(pages.count, 1))
            let aspect = paper.size.width / paper.size.height
            let maxW = (geo.size.width - gap * (count - 1)) / count
            let pageW = min(maxW, geo.size.height * aspect)
            let pageH = pageW / aspect
            let k = pageW / paper.size.width
            HStack(spacing: gap) {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, cards in
                    ZStack(alignment: .top) {
                        Rectangle().fill(Color.white)
                        VStack(spacing: 36 * k) {
                            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                                Image(uiImage: IDCardPDF.landscape(card))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: IDCardPDF.cardSize.width * k,
                                           height: IDCardPDF.cardSize.height * k)
                            }
                        }
                        .padding(.top, 72 * k)
                    }
                    .frame(width: pageW, height: pageH)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Card camera (own AVFoundation camera with a card guide)

final class CardCameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum Status { case starting, ready, denied, unavailable }

    let session = AVCaptureSession()
    @Published var status: Status = .starting
    @Published var torchOn = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "io.kopitiam.camera")
    private var device: AVCaptureDevice?
    private var completion: ((UIImage?) -> Void)?
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configureAndRun() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configureAndRun() {
        queue.async {
            if !self.configured {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                self.session.commitConfiguration()
                self.device = device
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .ready }
        }
    }

    func setTorch(_ on: Bool) {
        torchOn = on
        queue.async {
            guard let device = self.device, device.hasTorch else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    var hasTorch: Bool { device?.hasTorch ?? false }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        completion = done
        queue.async {
            if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:)).map(Self.upright)
        DispatchQueue.main.async {
            self.completion?(image)
            self.completion = nil
        }
    }

    /// Redraw so the pixels match the displayed orientation (.up).
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Crop the photo to the on-screen guide. The preview is aspect-fill, so map
    /// the guide back through the same scale and centring offset.
    static func crop(_ image: UIImage, guide: CGRect, in view: CGSize) -> UIImage {
        let iw = image.size.width * image.scale, ih = image.size.height * image.scale
        guard iw > 0, ih > 0, view.width > 0, view.height > 0 else { return image }
        let scale = max(view.width / iw, view.height / ih)
        let ox = (iw * scale - view.width) / 2
        let oy = (ih * scale - view.height) / 2
        // Allow a little slack around the guide so a refining pass can find the edges.
        let slack = guide.insetBy(dx: -guide.width * 0.06, dy: -guide.height * 0.06)
        let rect = CGRect(x: (slack.minX + ox) / scale, y: (slack.minY + oy) / scale,
                          width: slack.width / scale, height: slack.height / scale)
            .intersection(CGRect(x: 0, y: 0, width: iw, height: ih)).integral
        guard let cg = image.cgImage?.cropping(to: rect) else { return image }
        return UIImage(cgImage: cg)
    }

    /// Find the card's exact edges inside the crop and straighten it. Falls back
    /// to the plain guide crop when no card-shaped rectangle is found.
    static func refine(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.5
        request.maximumAspectRatio = 0.8
        request.minimumSize = 0.5
        request.minimumConfidence = 0.7
        request.quadratureTolerance = 20
        request.maximumObservations = 1
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: (1 - p.y) * h) }
        let quad = PerspectiveEngine.Quad(topLeft: px(obs.topLeft), topRight: px(obs.topRight),
                                          bottomRight: px(obs.bottomRight), bottomLeft: px(obs.bottomLeft))
        return PerspectiveEngine.correct(image, quad: quad)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// Fixed dark palette for the camera screens, whatever the app theme.
enum CameraUI {
    static let bg = Color(hex: "0E1412")
    static let panel = Color(hex: "1E2A26")
    static let text = Color(hex: "F4F1E9")
    static let soft = Color(hex: "B9C4BF")
    static let jade = Color(hex: "4FB99E")
    static let button = Color(hex: "1F6F5C")
}

/// Front, then back, with a card-shaped guide. Returns 1 or 2 straightened images.
struct CardCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CardCameraModel()
    let onComplete: ([UIImage]) -> Void

    @State private var captured: [UIImage] = []
    @State private var busy = false

    private var step: String { captured.isEmpty ? "Front" : "Back" }

    var body: some View {
        GeometryReader { geo in
            let guide = guideRect(in: geo.size)
            ZStack {
                CameraUI.bg.ignoresSafeArea()
                switch camera.status {
                case .ready, .starting:
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                    guideOverlay(guide, size: geo.size)
                case .denied:
                    message("Camera access is off",
                            "Turn on camera access for Kopitiam in Settings to scan ID cards.",
                            action: ("Open Settings", {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }))
                case .unavailable:
                    message("Scanning needs a camera",
                            "This device has no camera available, so ID card scanning is disabled here.",
                            action: nil)
                }
                controls(guide: guide, size: geo.size)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .statusBarHidden()
    }

    private func guideRect(in size: CGSize) -> CGRect {
        let width = size.width - 48
        let height = width / IDCardPDF.cardRatio
        return CGRect(x: 24, y: size.height * 0.40 - height / 2, width: width, height: height)
    }

    private func guideOverlay(_ guide: CGRect, size: CGSize) -> some View {
        ZStack {
            // Dim everything outside the card frame.
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: guide, cornerSize: CGSize(width: 16, height: 16))
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CameraUI.jade, lineWidth: 3)
                .frame(width: guide.width, height: guide.height)
                .position(x: guide.midX, y: guide.midY)
            Text(captured.isEmpty ? "Fit the front of the card in the frame" : "Now turn it over. Fit the back in the frame")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CameraUI.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(CameraUI.button, in: Capsule())
                .position(x: guide.midX, y: guide.minY - 34)
            Text("\(step) \(captured.count + 1) of 2")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CameraUI.text)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.black.opacity(0.55), in: Capsule())
                .position(x: guide.midX, y: guide.maxY + 28)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func controls(guide: CGRect, size: CGSize) -> some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                Spacer()
                if camera.status == .ready && camera.hasTorch {
                    Button { camera.setTorch(!camera.torchOn) } label: {
                        Image(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(camera.torchOn ? "Turn light off" : "Turn light on")
                }
            }
            .foregroundStyle(CameraUI.text)
            .padding(.horizontal, Space.md)

            Spacer()

            HStack {
                // Last captured side, as a small confirmation.
                Group {
                    if let last = captured.last {
                        Image(uiImage: last).resizable().scaledToFill()
                            .frame(width: 56, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(CameraUI.text.opacity(0.6)))
                            .accessibilityLabel("Front captured")
                    } else {
                        Color.clear.frame(width: 56, height: 36)
                    }
                }
                .frame(maxWidth: .infinity)

                Button { shoot(guide: guide, size: size) } label: {
                    ZStack {
                        Circle().strokeBorder(CameraUI.jade, lineWidth: 4).frame(width: 74, height: 74)
                        Circle().fill(CameraUI.text).frame(width: 58, height: 58)
                    }
                }
                .disabled(camera.status != .ready || busy)
                .opacity(camera.status == .ready ? 1 : 0.4)
                .accessibilityLabel("Capture \(step.lowercased())")

                Group {
                    if !captured.isEmpty {
                        Button("No back") { finish() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CameraUI.text)
                            .accessibilityHint("Save with the front only")
                    } else {
                        Color.clear.frame(width: 56, height: 36)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, Space.lg)
        }
    }

    private func message(_ title: String, _ body: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: Space.md) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(CameraUI.jade)
            Text(title).font(.title3.weight(.bold)).foregroundStyle(CameraUI.text)
            Text(body).font(.body).foregroundStyle(CameraUI.soft).multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .font(.headline)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(CameraUI.button, in: Capsule())
                    .foregroundStyle(CameraUI.text)
            }
        }
        .padding(Space.xl)
    }

    private func shoot(guide: CGRect, size: CGSize) {
        busy = true
        camera.capture { photo in
            guard let photo else { busy = false; return }
            DispatchQueue.global(qos: .userInitiated).async {
                let card = CardCameraModel.refine(CardCameraModel.crop(photo, guide: guide, in: size))
                DispatchQueue.main.async {
                    captured.append(card)
                    busy = false
                    if captured.count == 2 { finish() }
                }
            }
        }
    }

    private func finish() {
        camera.setTorch(false)
        onComplete(captured)
        dismiss()
    }
}

// MARK: - Scan hub (mode carousel)

enum ScanMode: String, CaseIterable, Identifiable {
    case scan, idCard, batch, text
    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: return "Scan"
        case .idCard: return "ID Cards"
        case .batch: return "Batch"
        case .text: return "Extract Text"
        }
    }

    var heading: String {
        switch self {
        case .scan: return "Scan a document"
        case .idCard: return "ID Cards"
        case .batch: return "Batch scan"
        case .text: return "Extract text"
        }
    }

    var blurb: String {
        switch self {
        case .scan: return "Kopitiam finds the edges and straightens each page. Saved as a PDF on this phone."
        case .idCard: return "Scan the front, then the back. Printed at the card's real size, on one page or two."
        case .batch: return "Receipts, a contract, a stack of forms. Every page lands in one PDF, in order."
        case .text: return "Point at printed text and get it back as text you can copy or share."
        }
    }

    /// Tool ids from the registry that open the hub at a given mode.
    init?(toolID: String) {
        switch toolID {
        case "document": self = .scan
        case "id-card": self = .idCard
        case "batch": self = .batch
        default: return nil
        }
    }
}

/// CamScanner-style launcher: one illustrated intro per mode, a Capture button,
/// and a mode carousel along the bottom. Always dark, like a camera.
struct ScanHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.kopi) private var kopi
    @State private var mode: ScanMode
    @State private var path: [HubRoute] = []
    @State private var showDocCamera = false
    @State private var showCardCamera = false
    @State private var cardSuggestion: [UIImage]?
    @State private var working = false
    @State private var error: String?

    enum HubRoute: Hashable {
        case idLayout(Int)
        case document(String)
        case text(Int)
    }

    /// Images and text for pushed screens, keyed by a counter (UIImage isn't Hashable).
    @State private var imageSets: [Int: [UIImage]] = [:]
    @State private var texts: [Int: String] = [:]
    @State private var nextKey = 0

    init(mode: ScanMode = .scan) { _mode = State(initialValue: mode) }

    var body: some View {
        NavigationStack(path: $path) {
            hub
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HubRoute.self) { route in
                    switch route {
                    case .idLayout(let key):
                        IDLayoutView(images: imageSets[key] ?? [],
                                     onSaved: { doc in path.append(.document(doc.id)) },
                                     onRetake: { path.removeAll(); showCardCamera = true })
                    case .document(let id):
                        DocumentDetailView(documentID: id)
                    case .text(let key):
                        TextResultView(text: texts[key] ?? "")
                    }
                }
        }
        .tint(kopi.accent)
        .fullScreenCover(isPresented: $showDocCamera) {
            DocumentScanner(
                onComplete: { images in showDocCamera = false; handleDocuments(images) },
                onCancel: { showDocCamera = false },
                onError: { msg in showDocCamera = false; error = msg })
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCardCamera) {
            CardCameraView { images in
                guard !images.isEmpty else { return }
                push(images: images)
            }
        }
        .confirmationDialog("This looks like an ID card",
                            isPresented: Binding(get: { cardSuggestion != nil },
                                                 set: { if !$0 { cardSuggestion = nil } }),
                            titleVisibility: .visible) {
            Button("Use the ID card layout") {
                if let images = cardSuggestion { push(images: images) }
                cardSuggestion = nil
            }
            Button("Keep as a normal scan") {
                if let images = cardSuggestion { saveScan(images) }
                cardSuggestion = nil
            }
        } message: {
            Text("Print it at the card's real size, with the front and back on one page or two.")
        }
    }

    private var hub: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                Spacer()
            }
            .foregroundStyle(CameraUI.text)
            .padding(.horizontal, Space.md)

            ScanModeArt(mode: mode)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                    let all = ScanMode.allCases
                    guard let i = all.firstIndex(of: mode) else { return }
                    if value.translation.width < -40, i + 1 < all.count { withAnimation(.kopiInteractive) { mode = all[i + 1] } }
                    if value.translation.width > 40, i > 0 { withAnimation(.kopiInteractive) { mode = all[i - 1] } }
                })

            VStack(spacing: Space.sm) {
                Text(mode.heading)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CameraUI.text)
                    .accessibilityAddTraits(.isHeader)
                Text(mode.blurb)
                    .font(.subheadline)
                    .foregroundStyle(CameraUI.soft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.md)

            Spacer(minLength: Space.md)

            if let error {
                Text(error).font(.footnote).foregroundStyle(Color(hex: "FF8A80"))
                    .padding(.horizontal, Space.lg)
            }

            Button(action: capture) {
                Text(working ? "Working…" : "Capture")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(CameraUI.button, in: Capsule())
                    .foregroundStyle(CameraUI.text)
            }
            .disabled(working)
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.sm)

            modeCarousel
                .padding(.top, Space.lg)
                .padding(.bottom, Space.md)
        }
        .background(CameraUI.bg.ignoresSafeArea())
    }

    private var modeCarousel: some View {
        HStack(spacing: Space.lg) {
            ForEach(ScanMode.allCases) { m in
                let on = m == mode
                Button { withAnimation(.kopiInteractive) { mode = m } } label: {
                    VStack(spacing: 6) {
                        Capsule().fill(on ? CameraUI.jade : Color.clear).frame(width: 28, height: 3)
                        Text(m.title)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? CameraUI.jade : CameraUI.soft)
                            .fixedSize()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func capture() {
        error = nil
        if mode == .idCard {
            showCardCamera = true
        } else if VNDocumentCameraViewController.isSupported {
            showDocCamera = true
        } else {
            error = "Scanning needs a camera, and this device doesn't have one."
        }
    }

    private func handleDocuments(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        switch mode {
        case .text:
            recognize(images)
        default:
            if images.count <= 2, images.allSatisfy(IDCardPDF.looksLikeCard) {
                cardSuggestion = images
            } else {
                saveScan(images)
            }
        }
    }

    private func push(images: [UIImage]) {
        let key = nextKey; nextKey += 1
        imageSets[key] = images
        path.append(.idLayout(key))
    }

    private func saveScan(_ images: [UIImage]) {
        do {
            let url = try PDFEngine.pdf(fromImages: images, outputName: "Scan.pdf")
            let prefix = mode == .batch ? "Batch" : "Scan"
            let doc = try DocumentStore.shared.save(url, title: DocumentStore.title(prefix))
            path.append(.document(doc.id))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func recognize(_ images: [UIImage]) {
        working = true
        DispatchQueue.global(qos: .userInitiated).async {
            let chunks = images.compactMap { try? OCREngine.recognize(image: $0).text }
            let text = chunks.joined(separator: "\n\n")
            DispatchQueue.main.async {
                working = false
                if text.isEmpty {
                    error = "No text was found. Try again with the page flat and well lit."
                } else {
                    let key = nextKey; nextKey += 1
                    texts[key] = text
                    path.append(.text(key))
                }
            }
        }
    }
}

/// Simple drawn illustration per mode (no photos), in brand colours on dark.
struct ScanModeArt: View {
    let mode: ScanMode

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "24332E"), CameraUI.bg], startPoint: .top, endPoint: .bottom)
            switch mode {
            case .scan: page(lines: 7).overlay(corners.padding(-14))
            case .idCard:
                ZStack {
                    card(Color(hex: "E8DCC8"), Color(hex: "C8B08A"), back: true)
                        .rotationEffect(.degrees(6)).offset(x: 28, y: 26)
                    card(Color(hex: "CFE3DC"), Color(hex: "8FBCAE"), back: false)
                        .rotationEffect(.degrees(-5)).offset(x: -20, y: -18)
                }
            case .batch:
                ZStack {
                    page(lines: 0).rotationEffect(.degrees(8)).offset(x: 22, y: 10).opacity(0.6)
                    page(lines: 0).rotationEffect(.degrees(-6)).offset(x: -18, y: 6).opacity(0.8)
                    page(lines: 7)
                }
            case .text:
                page(lines: 7, highlight: true)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func page(lines: Int, highlight: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: "F4F1E9"))
            VStack(alignment: .leading, spacing: 9) {
                ForEach(0..<lines, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(highlight && (i == 2 || i == 3) ? CameraUI.jade.opacity(0.7) : Color(hex: "1A1310").opacity(0.22))
                        .frame(width: i % 3 == 2 ? 70 : 110, height: 7)
                }
            }
            .padding(18)
        }
        .frame(width: 150, height: 200)
        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
    }

    private var corners: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, l: CGFloat = 26
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: w, y: h - l)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - l, y: h))
                p.move(to: CGPoint(x: l, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(CameraUI.jade, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    private func card(_ top: Color, _ bottom: Color, back: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            if back {
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.2))
                    .frame(width: 150, height: 18).offset(x: 16, y: 80)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.6))
                    .frame(width: 44, height: 58).offset(x: 16, y: 22)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.2))
                            .frame(width: i == 0 ? 90 : 70, height: 6)
                    }
                }
                .offset(x: 72, y: 30)
            }
        }
        .frame(width: 190, height: 190 / IDCardPDF.cardRatio)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
    }
}

/// Recognised text: selectable, copyable, shareable as a .txt file.
struct TextResultView: View {
    @Environment(\.kopi) private var kopi
    let text: String
    @State private var copied = false
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(kopi.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.md)
                    .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(kopi.line))
                HStack(spacing: Space.md) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .foregroundStyle(kopi.onBrand)
                    }
                    Button {
                        shareURL = try? OCREngine.writeTextFile(text)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(kopi.brand, lineWidth: 1.5))
                            .foregroundStyle(kopi.brand)
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(kopi.bg.ignoresSafeArea())
        .navigationTitle("Extracted text")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { shareURL.map(ShareURL.init) }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
    }
}

private struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
