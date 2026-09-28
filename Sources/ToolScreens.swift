import SwiftUI
import PDFKit
import UIKit

// MARK: - Shared result bar

private struct ResultActions: View {
    @Environment(\.kopi) private var kopi
    let urls: [URL]
    @State private var showShare = false
    var body: some View {
        Button {
            showShare = true
        } label: {
            Label(urls.count > 1 ? "Share \(urls.count) files" : "Save & Share",
                  systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .foregroundStyle(kopi.onBrand)
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: urls) }
    }
}

private struct ToolScaffold<Content: View>: View {
    @Environment(\.kopi) private var kopi
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            kopi.bg.ignoresSafeArea()
            ScrollView { VStack(alignment: .leading, spacing: Space.lg) { content() }
                .padding(Space.lg) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func primaryButton(_ title: String, kopi: KopiTheme, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .foregroundStyle(kopi.onBrand)
    }
}

// MARK: - Page thumbnail grid (multi-select)

private struct PageGrid: View {
    @Environment(\.kopi) private var kopi
    let document: PDFDocument
    @Binding var selection: Set<Int>
    let columns = [GridItem(.adaptive(minimum: 92), spacing: Space.md)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Space.md) {
            ForEach(0..<document.pageCount, id: \.self) { i in
                let on = selection.contains(i)
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        if let img = thumb(i) {
                            Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                                .frame(height: 120)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        }
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? kopi.accent : kopi.textSoft)
                            .padding(4).background(.thinMaterial, in: Circle()).padding(4)
                    }
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(on ? kopi.accent : kopi.line, lineWidth: on ? 2 : 1))
                    Text("\(i + 1)").font(.caption2).foregroundStyle(kopi.textSoft)
                }
                .pressable { if on { selection.remove(i) } else { selection.insert(i) } }
            }
        }
    }

    private func thumb(_ i: Int) -> UIImage? {
        document.page(at: i)?.thumbnail(of: CGSize(width: 160, height: 200), for: .mediaBox)
    }
}

// MARK: - Merge

struct MergeView: View {
    @Environment(\.kopi) private var kopi
    @State private var urls: [URL] = []
    @State private var picking = false
    @State private var output: URL?
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Merge PDF") {
            Text("Add two or more PDFs; they combine top to bottom in this order.")
                .font(.body).foregroundStyle(kopi.textSoft)
            ForEach(Array(urls.enumerated()), id: \.offset) { idx, u in
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(kopi.brand)
                    Text(u.lastPathComponent).lineLimit(1).foregroundStyle(kopi.text)
                    Spacer()
                    Text("\(idx + 1)").font(.caption).foregroundStyle(kopi.textSoft)
                }
                .padding(Space.sm)
                .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
            }
            Button { picking = true } label: {
                Label("Add PDF", systemImage: "plus").font(.headline).foregroundStyle(kopi.accent)
            }
            if urls.count >= 2 {
                primaryButton("Merge \(urls.count) PDFs", kopi: kopi) {
                    do { output = try PDFEngine.merge(urls); error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
            if let output { ResultActions(urls: [output]) }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker(allowsMultiple: true) { picked in urls.append(contentsOf: picked) }
        }
    }
}

// MARK: - Split

struct SplitView: View {
    @Environment(\.kopi) private var kopi
    @State private var doc: PDFDocument?
    @State private var picking = false
    @State private var outputs: [URL] = []
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Split PDF") {
            if let doc {
                Text("Splits into one file per page (\(doc.pageCount) files).")
                    .font(.body).foregroundStyle(kopi.textSoft)
                PageGridPreview(document: doc)
                primaryButton("Split into \(doc.pageCount) files", kopi: kopi) {
                    do {
                        outputs = try PDFEngine.split(doc.documentURL ?? saveTemp(doc),
                                                      ranges: (0..<doc.pageCount).map { $0...$0 })
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
                if !outputs.isEmpty { ResultActions(urls: outputs) }
            } else {
                Text("Choose a PDF to cut into separate files.")
                    .font(.body).foregroundStyle(kopi.textSoft)
                primaryButton("Choose a PDF", kopi: kopi) { picking = true }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { picked in if let u = picked.first { doc = PDFDocument(url: u) } }
        }
    }

    private func saveTemp(_ d: PDFDocument) -> URL {
        let u = PDFEngine.tempURL(name: "SplitSource.pdf"); d.write(to: u); return u
    }
}

// MARK: - Extract

struct ExtractView: View {
    @Environment(\.kopi) private var kopi
    @State private var doc: PDFDocument?
    @State private var picking = false
    @State private var selection = Set<Int>()
    @State private var output: URL?
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Extract Pages") {
            if let doc {
                Text("Select the pages to pull into a new PDF.")
                    .font(.body).foregroundStyle(kopi.textSoft)
                PageGrid(document: doc, selection: $selection)
                if !selection.isEmpty {
                    primaryButton("Extract \(selection.count) page\(selection.count == 1 ? "" : "s")", kopi: kopi) {
                        do {
                            let src = doc.documentURL ?? saveTemp(doc)
                            output = try PDFEngine.extract(src, pages: selection.sorted())
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
                if let output { ResultActions(urls: [output]) }
            } else {
                Text("Choose a PDF, then pick the pages you need.")
                    .font(.body).foregroundStyle(kopi.textSoft)
                primaryButton("Choose a PDF", kopi: kopi) { picking = true }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { picked in if let u = picked.first { doc = PDFDocument(url: u) } }
        }
    }

    private func saveTemp(_ d: PDFDocument) -> URL {
        let u = PDFEngine.tempURL(name: "ExtractSource.pdf"); d.write(to: u); return u
    }
}

// MARK: - Compress

struct CompressView: View {
    @Environment(\.kopi) private var kopi
    @State private var doc: PDFDocument?
    @State private var sourceURL: URL?
    @State private var picking = false
    @State private var quality: Double = 0.5
    @State private var output: URL?
    @State private var summary: String?
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Compress PDF") {
            if doc != nil {
                Text("Re-renders pages at lower quality to shrink the file. Best for scans and image-heavy PDFs (text becomes non-selectable).")
                    .font(.body).foregroundStyle(kopi.textSoft)
                VStack(alignment: .leading) {
                    Text("Quality: \(Int(quality * 100))%").font(.subheadline.weight(.semibold)).foregroundStyle(kopi.text)
                    Slider(value: $quality, in: 0.2...0.9)
                }
                primaryButton("Compress", kopi: kopi) {
                    do {
                        let src = sourceURL ?? saveTemp(doc!)
                        let r = try PDFEngine.compress(src, scale: 1.0, jpegQuality: quality)
                        output = r.url
                        summary = "\(byteStr(r.original)) → \(byteStr(r.compressed)) (\(pct(r.original, r.compressed)))"
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
                if let summary { Text(summary).font(.subheadline).foregroundStyle(kopi.accent) }
                if let output { ResultActions(urls: [output]) }
            } else {
                Text("Choose a PDF to shrink for sharing or upload.")
                    .font(.body).foregroundStyle(kopi.textSoft)
                primaryButton("Choose a PDF", kopi: kopi) { picking = true }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { picked in
                if let u = picked.first { sourceURL = u; doc = PDFDocument(url: u) }
            }
        }
    }

    private func saveTemp(_ d: PDFDocument) -> URL {
        let u = PDFEngine.tempURL(name: "CompressSource.pdf"); d.write(to: u); return u
    }
    private func byteStr(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
    private func pct(_ a: Int, _ b: Int) -> String {
        guard a > 0 else { return "—" }
        let saved = Double(a - b) / Double(a) * 100
        return saved >= 0 ? "-\(Int(saved))%" : "+\(Int(-saved))%"
    }
}

// MARK: - Redact (TRUE removal via rasterize+flatten)

struct RedactView: View {
    @Environment(\.kopi) private var kopi
    @State private var doc: PDFDocument?
    @State private var sourceURL: URL?
    @State private var picking = false
    @State private var pageIndex = 0
    @State private var boxes: [Int: [CGRect]] = [:]
    @State private var output: URL?
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Redact PDF") {
            if let doc {
                Text("Drag to draw redaction boxes. On export, each page you marked is flattened to an image so the covered text is truly removed — not selectable underneath.")
                    .font(.footnote).foregroundStyle(kopi.textSoft)
                RedactCanvas(document: doc, pageIndex: $pageIndex, boxes: $boxes)
                    .frame(height: 440)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(kopi.line))
                HStack {
                    Text("Page \(pageIndex + 1) of \(doc.pageCount)")
                        .font(.subheadline).foregroundStyle(kopi.text)
                    Spacer()
                    Button { if pageIndex > 0 { pageIndex -= 1 } } label: {
                        Image(systemName: "chevron.left").padding(8)
                    }.disabled(pageIndex == 0)
                    Button { if pageIndex < doc.pageCount - 1 { pageIndex += 1 } } label: {
                        Image(systemName: "chevron.right").padding(8)
                    }.disabled(pageIndex >= doc.pageCount - 1)
                }
                let count = boxes.values.reduce(0) { $0 + $1.count }
                if count > 0 {
                    primaryButton("Redact & flatten (\(count) box\(count == 1 ? "" : "es"))", kopi: kopi) {
                        do {
                            let src = sourceURL ?? saveTemp(doc)
                            output = try PDFEngine.redact(src, regions: boxes)
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
                if let output { ResultActions(urls: [output]) }
            } else {
                Text("Choose a PDF to black out sensitive content.")
                    .font(.body).foregroundStyle(kopi.textSoft)
                primaryButton("Choose a PDF", kopi: kopi) { picking = true }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { picked in
                if let u = picked.first { sourceURL = u; doc = PDFDocument(url: u) }
            }
        }
    }

    private func saveTemp(_ d: PDFDocument) -> URL {
        let u = PDFEngine.tempURL(name: "RedactSource.pdf"); d.write(to: u); return u
    }
}

// MARK: - Small non-interactive page preview grid

private struct PageGridPreview: View {
    let document: PDFDocument
    let columns = [GridItem(.adaptive(minimum: 80), spacing: 12)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<document.pageCount, id: \.self) { i in
                if let img = document.page(at: i)?.thumbnail(of: CGSize(width: 140, height: 180), for: .mediaBox) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(height: 110).background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
            }
        }
    }
}
