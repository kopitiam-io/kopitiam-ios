import SwiftUI

// MARK: - Warm Kopi palette + design tokens (matches the web app exactly)

extension Color {
    /// Hex initializer, e.g. Color(hex: "C05621").
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b, a: Double
        switch s.count {
        case 8: // RRGGBBAA
            r = Double((rgb >> 24) & 0xFF) / 255
            g = Double((rgb >> 16) & 0xFF) / 255
            b = Double((rgb >> 8) & 0xFF) / 255
            a = Double(rgb & 0xFF) / 255
        default: // RRGGBB
            r = Double((rgb >> 16) & 0xFF) / 255
            g = Double((rgb >> 8) & 0xFF) / 255
            b = Double(rgb & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Design tokens resolved for the current color scheme.
struct KopiTheme {
    let bg: Color
    let surface: Color
    let text: Color
    let textSoft: Color
    let line: Color
    let accent: Color
    let brand: Color
    let onBrand: Color

    static func light() -> KopiTheme {
        KopiTheme(
            bg: Color(hex: "F4F1E9"),
            surface: Color(hex: "FFFDF9"),
            text: Color(hex: "1A1310"),
            textSoft: Color(hex: "6B5D52"),
            line: Color(hex: "E7DCCB"),
            accent: Color(hex: "1F6F5C"),
            brand: Color(hex: "6F4E37"),
            onBrand: Color(hex: "F4F1E9")
        )
    }

    static func dark() -> KopiTheme {
        KopiTheme(
            bg: Color(hex: "17211E"),
            surface: Color(hex: "1F2B27"),
            text: Color(hex: "F4F1E9"),
            textSoft: Color(hex: "A9B8B0"),
            line: Color(hex: "2E3D38"),
            accent: Color(hex: "4FB99E"),
            brand: Color(hex: "C9A876"),
            onBrand: Color(hex: "17211E")
        )
    }

    static func resolve(_ scheme: ColorScheme) -> KopiTheme {
        scheme == .dark ? .dark() : .light()
    }
}

// MARK: - Nyonya tile band (brand signature)

/// A thin Peranakan-tile accent strip: kopi-brown lattice + jade dots on the
/// app background, capped by a jade grout line. The brand signature carried
/// across the site, Reddit assets, store feature graphic, and now the app.
struct NyonyaTileBand: View {
    var height: CGFloat = 18
    var tile: CGFloat = 18
    private let jade = Color(hex: "1F6F5C")
    private let jadeDark = Color(hex: "144E40")
    private let kopiBrown = Color(hex: "C68F52")

    var body: some View {
        Canvas { ctx, size in
            // Leave room for the grout line so the diamonds are never clipped.
            let grout: CGFloat = 2
            let h = size.height - grout - 1
            let step = tile
            let lw: CGFloat = 1.6
            // Centre the pattern so both ends finish on a whole diamond.
            let count = max(1, Int(size.width / step))
            let start = (size.width - CGFloat(count) * step) / 2
            for i in 0..<count {
                let x = start + CGFloat(i) * step
                let midY = h / 2 + lw / 2
                // Full diamond: left, top, right, bottom.
                var diamond = Path()
                diamond.move(to: CGPoint(x: x + lw / 2, y: midY))
                diamond.addLine(to: CGPoint(x: x + step / 2, y: lw / 2))
                diamond.addLine(to: CGPoint(x: x + step - lw / 2, y: midY))
                diamond.addLine(to: CGPoint(x: x + step / 2, y: h - lw / 2))
                diamond.closeSubpath()
                ctx.stroke(diamond, with: .color(kopiBrown), lineWidth: lw)
                // Jade dot in the centre of each tile.
                let r: CGFloat = 2.2
                ctx.fill(Path(ellipseIn: CGRect(x: x + step / 2 - r, y: midY - r, width: r * 2, height: r * 2)),
                         with: .color(jade))
            }
            // Jade grout line closing the band underneath.
            var line = Path()
            line.move(to: CGPoint(x: 0, y: size.height - grout / 2))
            line.addLine(to: CGPoint(x: size.width, y: size.height - grout / 2))
            ctx.stroke(line, with: .color(jadeDark), lineWidth: grout)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Radius scale.
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 22
    static let pill: CGFloat = 999
}

/// Spacing scale.
enum Space {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 36
}

/// Standard interaction spring (fluid-interface: fast, well-damped).
extension Animation {
    static var kopiInteractive: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: KopiTheme = .light()
}

extension EnvironmentValues {
    var kopi: KopiTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
