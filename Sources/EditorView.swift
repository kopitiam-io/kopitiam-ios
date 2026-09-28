import SwiftUI
import PDFKit
import UIKit

// MARK: - Editor tool modes

enum EditMode: String, CaseIterable, Identifiable {
    case view = "View"
    case text = "Text"
    case draw = "Draw"
    case highlight = "Highlight"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .view: return "hand.point.up.left"
        case .text: return "textformat"
        case .draw: return "scribble.variable"
        case .highlight: return "highlighter"
        }
    }
}

// MARK: - Editor screen

struct EditorView: View {
    @Environment(\.kopi) private var kopi
    @StateObject private var model = EditorModel()
    @State private var showImporter = false
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var errorText: String?
    var autoloadSample: Bool = false

    var body: some View {
        ZStack {
            kopi.bg.ignoresSafeArea()
            if let doc = model.document {
                VStack(spacing: 0) {
                    PDFCanvas(document: doc, mode: model.mode, ink: kopi.accent)
                        .ignoresSafeArea(edges: .bottom)
                    toolbar
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Edit PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.document != nil {
                    Button {
                        do { shareURL = try model.export(); showShare = true }
                        catch { errorText = error.localizedDescription }
                    } label: {
                        Label("Save & Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                if let u = urls.first { model.load(u) }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .alert("Couldn’t complete that", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
        .onAppear {
            if autoloadSample && model.document == nil { model.loadSample() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(kopi.brand)
            Text("Open a PDF to edit")
                .font(.title2.weight(.bold))
                .foregroundStyle(kopi.text)
            Text("Add text, draw, and highlight on real pages.")
                .font(.body).foregroundStyle(kopi.textSoft)
                .multilineTextAlignment(.center)
            VStack(spacing: Space.sm) {
                Button {
                    showImporter = true
                } label: {
                    Text("Choose a PDF")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .foregroundStyle(kopi.onBrand)
                }
                Button {
                    model.loadSample()
                } label: {
                    Text("Try a sample document")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(kopi.accent)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.sm)
        }
        .padding(Space.lg)
    }

    private var toolbar: some View {
        HStack(spacing: Space.sm) {
            ForEach(EditMode.allCases) { mode in
                let selected = model.mode == mode
                VStack(spacing: 4) {
                    Image(systemName: mode.symbol).font(.system(size: 18, weight: .semibold))
                    Text(mode.rawValue).font(.caption2.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? kopi.onBrand : kopi.text)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(selected ? kopi.brand : kopi.surface)
                )
                .pressable { model.mode = mode }
            }
        }
        .padding(Space.sm)
        .background(kopi.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(kopi.line), alignment: .top)
    }
}

// MARK: - Editor model

final class EditorModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var mode: EditMode = .view

    func load(_ url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        if let doc = PDFDocument(url: url) { document = doc }
    }

    func loadSample() {
        if let url = PDFEngine.makeSampleDocument(), let doc = PDFDocument(url: url) {
            document = doc
        }
    }

    func export() throws -> URL {
        guard let doc = document else { throw PDFEngine.EngineError.emptyResult }
        return try PDFEngine.save(doc, outputName: "Kopitiam-Edited.pdf")
    }
}

// MARK: - PDFView wrapper with annotation gestures

struct PDFCanvas: UIViewRepresentable {
    let document: PDFDocument
    let mode: EditMode
    let ink: Color

    func makeCoordinator() -> Coordinator { Coordinator(ink: UIColor(ink)) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = document
        context.coordinator.pdfView = view

        // Tap for text placement.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        // Pan for ink + highlight (1:1 direct manipulation).
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        context.coordinator.tap = tap
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.mode = mode
        if view.document !== document { view.document = document }
        // While drawing/highlighting, disable PDFView's own pan so our gesture wins.
        context.coordinator.pan?.isEnabled = true
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var pdfView: PDFView?
        var mode: EditMode = .view
        let ink: UIColor
        var pan: UIPanGestureRecognizer?
        var tap: UITapGestureRecognizer?

        // In-progress ink stroke.
        private var inkPage: PDFPage?
        private var inkPoints: [CGPoint] = []
        private var liveInk: PDFAnnotation?
        // In-progress highlight.
        private var hlPage: PDFPage?
        private var hlStart: CGPoint = .zero

        init(ink: UIColor) { self.ink = ink }

        // MARK: Tap → freeText
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard mode == .text, let view = pdfView else { return }
            let loc = g.location(in: view)
            guard let page = view.page(for: loc, nearest: true) else { return }
            let pagePoint = view.convert(loc, to: page)
            let bounds = CGRect(x: pagePoint.x, y: pagePoint.y - 20, width: 200, height: 32)
            let ann = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            ann.contents = "Text"
            ann.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            ann.fontColor = ink
            ann.color = .clear
            page.addAnnotation(ann)
        }

        // MARK: Pan → ink or highlight
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            switch mode {
            case .draw:      handleInk(g)
            case .highlight: handleHighlight(g)
            default:         break
            }
        }

        private func handleInk(_ g: UIPanGestureRecognizer) {
            guard let view = pdfView else { return }
            let loc = g.location(in: view)
            switch g.state {
            case .began:
                guard let page = view.page(for: loc, nearest: true) else { return }
                inkPage = page
                inkPoints = [view.convert(loc, to: page)]
            case .changed:
                guard let page = inkPage else { return }
                inkPoints.append(view.convert(loc, to: page))
                redrawLiveInk(on: page)
            case .ended, .cancelled, .failed:
                if let page = inkPage { redrawLiveInk(on: page) }
                inkPage = nil; inkPoints = []; liveInk = nil
            default: break
            }
        }

        private func redrawLiveInk(on page: PDFPage) {
            if let existing = liveInk { page.removeAnnotation(existing) }
            guard inkPoints.count > 1 else { return }
            let path = UIBezierPath()
            path.move(to: inkPoints[0])
            for p in inkPoints.dropFirst() { path.addLine(to: p) }
            let bounds = page.bounds(for: .mediaBox)
            let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            let border = PDFBorder(); border.lineWidth = 2.5
            ann.border = border
            ann.color = ink
            ann.add(path)
            page.addAnnotation(ann)
            liveInk = ann
        }

        private func handleHighlight(_ g: UIPanGestureRecognizer) {
            guard let view = pdfView else { return }
            let loc = g.location(in: view)
            switch g.state {
            case .began:
                guard let page = view.page(for: loc, nearest: true) else { return }
                hlPage = page
                hlStart = view.convert(loc, to: page)
            case .ended:
                guard let page = hlPage else { return }
                let end = view.convert(loc, to: page)
                let rect = CGRect(x: min(hlStart.x, end.x), y: min(hlStart.y, end.y),
                                  width: abs(end.x - hlStart.x), height: abs(end.y - hlStart.y))
                if rect.width > 4 && rect.height > 4 {
                    let ann = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                    ann.color = UIColor.systemYellow.withAlphaComponent(0.45)
                    page.addAnnotation(ann)
                }
                hlPage = nil
            default: break
            }
        }

        // Let our pan coexist; only intercept when a draw/highlight mode is active.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if g === pan { return mode == .view }
            return true
        }
    }
}
