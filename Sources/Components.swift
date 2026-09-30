import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Press-response scale (fluid interface: respond on touch-down)

struct PressableScale: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var pressed = false
    var scale: CGFloat = 0.97
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? scale : 1.0)
            .animation(reduceMotion ? nil : .kopiInteractive, value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { value in
                        // Only fire if the finger stayed on the view (a tap).
                        let d = value.translation
                        if abs(d.width) < 12 && abs(d.height) < 12 { action() }
                    }
            )
    }
}

extension View {
    func pressable(scale: CGFloat = 0.97, action: @escaping () -> Void) -> some View {
        modifier(PressableScale(scale: scale, action: action))
    }
}

// MARK: - Tool card (2-col grid tile)

struct ToolCard: View {
    let tool: Tool
    @Environment(\.kopi) private var kopi

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Image(systemName: tool.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(kopi.accent)
                    .frame(width: 44, height: 44)
                Spacer()
                if tool.comingSoon {
                    Text("Soon")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(kopi.accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(kopi.accent)
                }
            }
            Text(tool.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(kopi.text)
            Text(tool.blurb)
                .font(.subheadline)
                .foregroundStyle(kopi.textSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(kopi.line, lineWidth: 1)
        )
        .opacity(tool.comingSoon ? 0.72 : 1)
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Document picker (import PDFs)

struct DocumentPicker: UIViewControllerRepresentable {
    var allowsMultiple: Bool = false
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        vc.allowsMultipleSelection = allowsMultiple
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - Photo library picker (import images for Convert → image→PDF)

/// PHPicker-based multi-image importer. `selectionLimit: 0` means unlimited.
/// Loads the picked items as UIImages and returns them in selection order.
struct ImagePicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 0
    let onComplete: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([UIImage]) -> Void
        init(onComplete: @escaping ([UIImage]) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { onComplete([]); return }
            // Preserve order: load into a fixed-size array by index.
            var images = [UIImage?](repeating: nil, count: results.count)
            let group = DispatchGroup()
            for (idx, result) in results.enumerated() {
                let provider = result.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { images[idx] = img }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.onComplete(images.compactMap { $0 })
            }
        }
    }
}
