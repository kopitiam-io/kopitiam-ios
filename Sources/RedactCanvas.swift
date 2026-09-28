import SwiftUI
import PDFKit
import UIKit

/// Renders one PDF page and captures drag-drawn redaction rectangles.
/// Boxes are stored keyed by page index in PDF page coordinates (origin
/// bottom-left, points) so PDFEngine.redact can flatten them exactly.
struct RedactCanvas: View {
    let document: PDFDocument
    @Binding var pageIndex: Int
    @Binding var boxes: [Int: [CGRect]]

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let page = document.page(at: pageIndex)
            let pageBounds = page?.bounds(for: .mediaBox) ?? .zero
            let fit = fitRect(content: pageBounds.size, into: geo.size)

            ZStack {
                if let img = page?.thumbnail(of: CGSize(width: pageBounds.width, height: pageBounds.height), for: .mediaBox) {
                    Image(uiImage: img).resizable().frame(width: fit.width, height: fit.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                // Committed boxes for this page (drawn in view space).
                ForEach(Array((boxes[pageIndex] ?? []).enumerated()), id: \.offset) { _, r in
                    let v = pdfRectToView(r, pageBounds: pageBounds, fit: fit, canvas: geo.size)
                    Rectangle().fill(Color.black)
                        .frame(width: v.width, height: v.height)
                        .position(x: v.midX, y: v.midY)
                }
                // Live drag box.
                if let s = dragStart, let c = dragCurrent {
                    let r = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                                   width: abs(c.x - s.x), height: abs(c.y - s.y))
                    Rectangle().fill(Color.black.opacity(0.55))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        if dragStart == nil { dragStart = g.startLocation }
                        dragCurrent = g.location
                    }
                    .onEnded { _ in
                        guard let s = dragStart, let c = dragCurrent else { return }
                        let viewRect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                                              width: abs(c.x - s.x), height: abs(c.y - s.y))
                        if viewRect.width > 6 && viewRect.height > 6 {
                            let pdfRect = viewRectToPDF(viewRect, pageBounds: pageBounds, fit: fit, canvas: geo.size)
                            boxes[pageIndex, default: []].append(pdfRect)
                        }
                        dragStart = nil; dragCurrent = nil
                    }
            )
        }
    }

    // Aspect-fit the page inside the canvas.
    private func fitRect(content: CGSize, into canvas: CGSize) -> CGSize {
        guard content.width > 0, content.height > 0 else { return canvas }
        let scale = min(canvas.width / content.width, canvas.height / content.height)
        return CGSize(width: content.width * scale, height: content.height * scale)
    }

    private func originOffset(fit: CGSize, canvas: CGSize) -> CGPoint {
        CGPoint(x: (canvas.width - fit.width) / 2, y: (canvas.height - fit.height) / 2)
    }

    // View (top-left) → PDF page (bottom-left) coordinates.
    private func viewRectToPDF(_ r: CGRect, pageBounds: CGRect, fit: CGSize, canvas: CGSize) -> CGRect {
        let off = originOffset(fit: fit, canvas: canvas)
        let sx = pageBounds.width / fit.width
        let sy = pageBounds.height / fit.height
        let localX = (r.origin.x - off.x) * sx
        let localTopY = (r.origin.y - off.y) * sy
        let w = r.width * sx
        let h = r.height * sy
        // Flip Y: view top-left → PDF bottom-left.
        let pdfY = pageBounds.height - localTopY - h
        return CGRect(x: pageBounds.origin.x + localX,
                      y: pageBounds.origin.y + pdfY,
                      width: w, height: h)
    }

    // PDF page (bottom-left) → View (top-left) coordinates.
    private func pdfRectToView(_ r: CGRect, pageBounds: CGRect, fit: CGSize, canvas: CGSize) -> CGRect {
        let off = originOffset(fit: fit, canvas: canvas)
        let sx = fit.width / pageBounds.width
        let sy = fit.height / pageBounds.height
        let localX = (r.origin.x - pageBounds.origin.x) * sx
        let w = r.width * sx
        let h = r.height * sy
        let localTopY = (pageBounds.height - (r.origin.y - pageBounds.origin.y) - r.height) * sy
        return CGRect(x: off.x + localX, y: off.y + localTopY, width: w, height: h)
    }
}
