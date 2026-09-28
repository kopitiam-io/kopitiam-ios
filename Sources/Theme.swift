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
            bg: Color(hex: "F7F1E8"),
            surface: Color(hex: "FFFDF9"),
            text: Color(hex: "1A1310"),
            textSoft: Color(hex: "6B5D52"),
            line: Color(hex: "E7DCCB"),
            accent: Color(hex: "C05621"),
            brand: Color(hex: "6F4E37"),
            onBrand: Color(hex: "F7F1E8")
        )
    }

    static func dark() -> KopiTheme {
        KopiTheme(
            bg: Color(hex: "2A1A12"),
            surface: Color(hex: "33251C"),
            text: Color(hex: "F7F1E8"),
            textSoft: Color(hex: "C9A876"),
            line: Color(hex: "4A3628"),
            accent: Color(hex: "E9843F"),
            brand: Color(hex: "C9A876"),
            onBrand: Color(hex: "2A1A12")
        )
    }

    static func resolve(_ scheme: ColorScheme) -> KopiTheme {
        scheme == .dark ? .dark() : .light()
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
