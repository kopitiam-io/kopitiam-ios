import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import PDFKit
import UIKit

// MARK: - Perspective correction engine

/// Core Image perspective correction, plus a Vision rectangle detector to seed
/// the initial corner positions from the largest detected quadrilateral.
enum PerspectiveEngine {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Four corners in image space (pixels, top-left origin as UIKit uses).
    struct Quad {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomRight: CGPoint
        var bottomLeft: CGPoint
    }

    /// Detect the most prominent rectangle in the image; returns a Quad in UIKit
    /// pixel coordinates, or a default inset quad if none is found.
    static func detectQuad(in image: UIImage) -> Quad {
        let px = CGSize(width: image.cgImage?.width ?? Int(image.size.width),
                        height: image.cgImage?.height ?? Int(image.size.height))
        let fallback = Quad(
            topLeft: CGPoint(x: px.width * 0.1, y: px.height * 0.1),
            topRight: CGPoint(x: px.width * 0.9, y: px.height * 0.1),
            bottomRight: CGPoint(x: px.width * 0.9, y: px.height * 0.9),
            bottomLeft: CGPoint(x: px.width * 0.1, y: px.height * 0.9))
        guard let cg = image.cgImage else { return fallback }

        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.2
        request.maximumObservations = 1
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first else { return fallback }

        // Vision points are normalized, bottom-left origin → convert to UIKit px.
        func toPx(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * px.width, y: (1 - p.y) * px.height)
        }
        return Quad(
            topLeft: toPx(obs.topLeft),
            topRight: toPx(obs.topRight),
            bottomRight: toPx(obs.bottomRight),
            bottomLeft: toPx(obs.bottomLeft))
    }

    /// Apply CIPerspectiveCorrection using corners in UIKit pixel space.
    static func correct(_ image: UIImage, quad: Quad) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        let h = ci.extent.height
        // CIImage uses bottom-left origin; flip Y from UIKit corners.
        func toCI(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: h - p.y) }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ci
        filter.topLeft = toCI(quad.topLeft)
        filter.topRight = toCI(quad.topRight)
        filter.bottomRight = toCI(quad.bottomRight)
        filter.bottomLeft = toCI(quad.bottomLeft)
        guard let out = filter.outputImage,
              let cg = context.createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
}

// MARK: - Corner-drag canvas

/// Shows the image aspect-fit and four draggable corner handles. Corners are
/// stored in image pixel space; the view maps to/from its own layout.
private struct CornerDragCanvas: View {
    @Environment(\.kopi) private var kopi
    let image: UIImage
    @Binding var quad: PerspectiveEngine.Quad

    var body: some View {
        GeometryReader { geo in
            let imgSize = CGSize(width: image.cgImage?.width ?? Int(image.size.width),
                                 height: image.cgImage?.height ?? Int(image.size.height))
            let fit = fitRect(content: imgSize, into: geo.size)
            let off = CGPoint(x: (geo.size.width - fit.width) / 2,
                              y: (geo.size.height - fit.height) / 2)

            ZStack {
                Image(uiImage: image).resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Quad outline
                Path { p in
                    let pts = viewCorners(imgSize: imgSize, fit: fit, off: off)
                    p.move(to: pts[0])
                    p.addLine(to: pts[1]); p.addLine(to: pts[2]); p.addLine(to: pts[3])
                    p.closeSubpath()
                }
                .stroke(kopi.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                // Handles
                ForEach(0..<4, id: \.self) { i in
                    let pts = viewCorners(imgSize: imgSize, fit: fit, off: off)
                    Circle()
                        .fill(kopi.accent)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .position(pts[i])
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    let clamped = CGPoint(
                                        x: min(max(g.location.x, off.x), off.x + fit.width),
                                        y: min(max(g.location.y, off.y), off.y + fit.height))
                                    setCorner(i, view: clamped, imgSize: imgSize, fit: fit, off: off)
                                }
                        )
                }
            }
        }
    }

    private func fitRect(content: CGSize, into canvas: CGSize) -> CGSize {
        guard content.width > 0, content.height > 0 else { return canvas }
        let scale = min(canvas.width / content.width, canvas.height / content.height)
        return CGSize(width: content.width * scale, height: content.height * scale)
    }

    private func imgToView(_ p: CGPoint, imgSize: CGSize, fit: CGSize, off: CGPoint) -> CGPoint {
        CGPoint(x: off.x + p.x / imgSize.width * fit.width,
                y: off.y + p.y / imgSize.height * fit.height)
    }
    private func viewToImg(_ p: CGPoint, imgSize: CGSize, fit: CGSize, off: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - off.x) / fit.width * imgSize.width,
                y: (p.y - off.y) / fit.height * imgSize.height)
    }
    private func viewCorners(imgSize: CGSize, fit: CGSize, off: CGPoint) -> [CGPoint] {
        [imgToView(quad.topLeft, imgSize: imgSize, fit: fit, off: off),
         imgToView(quad.topRight, imgSize: imgSize, fit: fit, off: off),
         imgToView(quad.bottomRight, imgSize: imgSize, fit: fit, off: off),
         imgToView(quad.bottomLeft, imgSize: imgSize, fit: fit, off: off)]
    }
    private func setCorner(_ i: Int, view: CGPoint, imgSize: CGSize, fit: CGSize, off: CGPoint) {
        let p = viewToImg(view, imgSize: imgSize, fit: fit, off: off)
        switch i {
        case 0: quad.topLeft = p
        case 1: quad.topRight = p
        case 2: quad.bottomRight = p
        default: quad.bottomLeft = p
        }
    }
}

// MARK: - Screen

struct PerspectiveRefineView: View {
    @Environment(\.kopi) private var kopi
    @State private var sourceImage: UIImage?
    @State private var quad = PerspectiveEngine.Quad(topLeft: .zero, topRight: .zero,
                                                     bottomRight: .zero, bottomLeft: .zero)
    @State private var corrected: UIImage?
    @State private var output: URL?
    @State private var picking = false
    @State private var error: String?
    /// Load the sample page on appear (sim verification of the corner canvas).
    var autorun: Bool = false

    var body: some View {
        ZStack {
            kopi.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Straighten a photographed page. Kopitiam guesses the edges — drag any corner to fine-tune, then flatten.")
                        .font(.body).foregroundStyle(kopi.textSoft)

                    if let sourceImage {
                        CornerDragCanvas(image: sourceImage, quad: $quad)
                            .frame(height: 380)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(kopi.line))

                        Button(action: applyCorrection) {
                            Label("Straighten", systemImage: "crop.rotate")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .foregroundStyle(kopi.onBrand)
                        }

                        if let corrected {
                            Text("Corrected").font(.subheadline.weight(.semibold)).foregroundStyle(kopi.text)
                            Image(uiImage: corrected).resizable().aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 320)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(kopi.line))
                            if let output {
                                Button {
                                    share(output)
                                } label: {
                                    Label("Save as PDF & Share", systemImage: "square.and.arrow.up")
                                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                                        .background(kopi.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        Button("Choose a different image") { picking = true }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
                    } else {
                        Button { picking = true } label: {
                            Label("Choose an image", systemImage: "photo")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(kopi.brand, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .foregroundStyle(kopi.onBrand)
                        }
                        Button("Use a rendered sample page") { loadSample() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(kopi.accent)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                .padding(Space.lg)
            }
        }
        .navigationTitle("Fix Perspective")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            ImagePicker(selectionLimit: 1) { imgs in
                if let img = imgs.first { load(img) }
            }
        }
        .sheet(item: Binding(get: { shareItem }, set: { shareItem = $0 })) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear {
            if autorun && sourceImage == nil { loadSample() }
        }
    }

    // Share sheet plumbing
    struct ShareItem: Identifiable { let id = UUID(); let url: URL }
    @State private var shareItem: ShareItem?

    private func load(_ img: UIImage) {
        sourceImage = img
        quad = PerspectiveEngine.detectQuad(in: img)
        corrected = nil; output = nil; error = nil
    }

    private func loadSample() {
        // Render the sample PDF's first page as a stand-in "photographed page".
        if let u = PDFEngine.makeSampleDocument(), let doc = PDFDocument(url: u),
           let page = doc.page(at: 0), let img = OCREngine.renderPageImage(page, scale: 2.0) {
            load(img)
        } else {
            error = "Could not load a sample image."
        }
    }

    private func applyCorrection() {
        guard let sourceImage else { return }
        let result = PerspectiveEngine.correct(sourceImage, quad: quad)
        corrected = result
        do {
            output = try PDFEngine.pdf(fromImages: [result], outputName: "Straightened.pdf")
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func share(_ url: URL) { shareItem = ShareItem(url: url) }
}
