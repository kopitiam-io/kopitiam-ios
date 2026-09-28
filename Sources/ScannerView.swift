import SwiftUI
import VisionKit
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
                output = try PDFEngine.stackedPDF(fromImages: images, outputName: outputName)
                pageCount = 1
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
