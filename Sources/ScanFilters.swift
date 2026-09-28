import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Core Image-backed scan filters: the CamScanner-style enhancement modes applied
/// to a captured/loaded page image. Each mode returns a new UIImage; a shared
/// `CIContext` is reused for performance.
enum ScanFilters {

    /// Available enhancement modes.
    enum Mode: String, CaseIterable, Identifiable {
        case original   = "Original"
        case autoEnhance = "Auto"
        case magicColor = "Magic Color"
        case grayscale  = "Grayscale"
        case blackWhite = "B&W"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .original:    return "photo"
            case .autoEnhance: return "wand.and.stars"
            case .magicColor:  return "paintpalette"
            case .grayscale:   return "circle.lefthalf.filled"
            case .blackWhite:  return "circle.righthalf.filled"
            }
        }
        var blurb: String {
            switch self {
            case .original:    return "No changes."
            case .autoEnhance: return "Balance exposure and sharpen."
            case .magicColor:  return "Whiten the page, keep color ink."
            case .grayscale:   return "Neutral gray tones."
            case .blackWhite:  return "High-contrast document scan."
            }
        }
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Apply a mode to an image, returning a rendered UIImage (or the original on
    /// any failure — filters never crash the flow).
    static func apply(_ mode: Mode, to image: UIImage) -> UIImage {
        guard mode != .original, let ci = CIImage(image: image) else { return image }
        let output: CIImage?
        switch mode {
        case .original:    output = ci
        case .autoEnhance: output = autoEnhance(ci)
        case .magicColor:  output = magicColor(ci)
        case .grayscale:   output = grayscale(ci)
        case .blackWhite:  output = blackWhite(ci)
        }
        guard let out = output,
              let cg = context.createCGImage(out, from: ci.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Modes

    /// Balance exposure + a touch of contrast and sharpening.
    private static func autoEnhance(_ ci: CIImage) -> CIImage? {
        var img = ci
        // Apple's built-in auto-adjustment chain (exposure/contrast/etc.).
        for filter in img.autoAdjustmentFilters(options: [.enhance: true]) {
            filter.setValue(img, forKey: kCIInputImageKey)
            if let out = filter.outputImage { img = out }
        }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = img
        sharpen.sharpness = 0.4
        return sharpen.outputImage ?? img
    }

    /// "Magic Color": lift and whiten the background while keeping colored ink —
    /// gentle exposure lift + contrast + slight saturation so a photographed page
    /// reads like a clean scan.
    private static func magicColor(_ ci: CIImage) -> CIImage? {
        let controls = CIFilter.colorControls()
        controls.inputImage = ci
        controls.brightness = 0.06
        controls.contrast = 1.18
        controls.saturation = 1.08
        guard let boosted = controls.outputImage else { return ci }
        // Nudge the white point so the paper goes clean-white.
        let tone = CIFilter.toneCurve()
        tone.inputImage = boosted
        tone.point0 = CGPoint(x: 0.0, y: 0.0)
        tone.point1 = CGPoint(x: 0.25, y: 0.22)
        tone.point2 = CGPoint(x: 0.5, y: 0.55)
        tone.point3 = CGPoint(x: 0.75, y: 0.85)
        tone.point4 = CGPoint(x: 0.92, y: 1.0)
        return tone.outputImage ?? boosted
    }

    /// Neutral grayscale.
    private static func grayscale(_ ci: CIImage) -> CIImage? {
        let mono = CIFilter.photoEffectMono()
        mono.inputImage = ci
        return mono.outputImage
    }

    /// High-contrast black & white document scan: grayscale, boosted contrast,
    /// then a monochrome threshold-like curve. Approximates adaptive thresholding
    /// with a strong tone curve (no non-built-in kernels required).
    private static func blackWhite(_ ci: CIImage) -> CIImage? {
        let mono = CIFilter.colorControls()
        mono.inputImage = ci
        mono.saturation = 0.0
        mono.contrast = 1.1
        guard let gray = mono.outputImage else { return ci }
        // Steep tone curve to push toward black/white while keeping anti-aliasing.
        let tone = CIFilter.toneCurve()
        tone.inputImage = gray
        tone.point0 = CGPoint(x: 0.0, y: 0.0)
        tone.point1 = CGPoint(x: 0.35, y: 0.05)
        tone.point2 = CGPoint(x: 0.5, y: 0.5)
        tone.point3 = CGPoint(x: 0.62, y: 0.95)
        tone.point4 = CGPoint(x: 1.0, y: 1.0)
        return tone.outputImage
    }
}
