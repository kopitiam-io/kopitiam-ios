import SwiftUI
import UIKit

// MARK: - House ad inventory (mirrors web src/components/HouseAd.tsx)
//
// Kopitiam's own fallback/brand inventory. There is NO Slate integration on
// native yet, so the slot always shows a HOUSE ad directly (no serve / no-fill
// path). Three interchangeable organic directions, picked once per mounted slot
// so it doesn't flicker on re-render:
//   .steam — brand motif (kopi cup + rising steam), email-first CTA
//   .tools — cross-promo of Kopitiam's own tools (auto-advances, taps navigate)
//   .sweep — quiet editorial "Advertise here"
// The web-only "sampan" cross-promo is deliberately omitted here.
// All motion is transform/opacity and freezes under Reduce Motion.

enum HouseKind: CaseIterable { case steam, tools, sweep }

enum AdCopy {
    static let contactEmail = "hello@kopitiam.io"
    static let bookingURL = "https://calendly.com/ethan-kopitiam/30min"
    static let enquirySubject = "Advertising enquiry — Kopitiam"
    static let enquiryBody = [
        "Hi Kopitiam team,",
        "",
        "We'd like to advertise on Kopitiam. A few details:",
        "",
        "• Company / product:",
        "• What you want to promote:",
        "• Target audience:",
        "• Monthly budget (rough is fine):",
        "• Preferred start date:",
        "",
        "Thanks!",
    ].joined(separator: "\n")

    /// mailto: URL with the standard advertising subject + prefilled body.
    static var mailtoURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = contactEmail
        c.queryItems = [
            URLQueryItem(name: "subject", value: enquirySubject),
            URLQueryItem(name: "body", value: enquiryBody),
        ]
        return c.url
    }

    static var booking: URL? { URL(string: bookingURL) }
}

/// Cross-promo of Kopitiam's own tools. `toolID` maps to a ToolRegistry id so a
/// tap can navigate in-app. `soon` items read as teasers.
struct ToolPromo: Identifiable, Hashable {
    let id = UUID()
    let head: String
    let sub: String
    let toolID: String
    var soon: Bool = false
}

enum HouseAdData {
    static let toolPromos: [ToolPromo] = [
        ToolPromo(head: "Merge PDFs", sub: "Combine files in seconds — free", toolID: "merge"),
        ToolPromo(head: "Fill any form", sub: "Auto-detected fields, no typing hunts", toolID: "edit"),
        ToolPromo(head: "Split & extract", sub: "Pull the pages you need", toolID: "split"),
        ToolPromo(head: "No sign-up", sub: "Open a tab, drop a file, done", toolID: "edit"),
        ToolPromo(head: "Convert PDFs", sub: "To Word, Excel & images — coming soon", toolID: "convert", soon: true),
        ToolPromo(head: "Compress PDFs", sub: "Shrink big files to share — coming soon", toolID: "compress", soon: true),
    ]
}

private func openURL(_ url: URL?) {
    guard let url else { return }
    UIApplication.shared.open(url)
}

// MARK: - AdSlot (native equivalent of AdSlot.tsx)

/// The single native ad slot. No Slate serve logic — it renders a house ad
/// directly. The kind is chosen ONCE on mount and stays stable for the slot's
/// lifetime. `onOpenTool` lets a tapped tool-promo navigate in-app.
struct AdSlotView: View {
    @Environment(\.kopi) private var kopi
    var force: HouseKind? = nil
    var onOpenTool: (String) -> Void = { _ in }

    @State private var kind: HouseKind = .steam

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Advertise here")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(kopi.textSoft.opacity(0.8))
            HouseAdView(kind: kind, onOpenTool: onOpenTool)
        }
        .onAppear {
            // Stable per slot lifetime: pick only if not forced and not yet set
            // beyond the default. Guard so re-appear doesn't reroll.
            if let force { kind = force }
        }
        .task {
            if force == nil { kind = HouseKind.allCases.randomElement() ?? .steam }
        }
    }
}

// MARK: - HouseAd (native equivalent of HouseAd.tsx)

struct HouseAdView: View {
    let kind: HouseKind
    var onOpenTool: (String) -> Void = { _ in }

    var body: some View {
        switch kind {
        case .steam: HouseSteam()
        case .tools: HouseTools(onOpenTool: onOpenTool)
        case .sweep: HouseSweep()
        }
    }
}

// MARK: - Shared leaderboard chrome

private struct AdCard: ViewModifier {
    @Environment(\.kopi) private var kopi
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(Space.md)
            .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(kopi.line, lineWidth: 1)
            )
    }
}

private extension View {
    func adCard() -> some View { modifier(AdCard()) }
}

private struct AdPillButton: View {
    @Environment(\.kopi) private var kopi
    let title: String
    let symbol: String
    var ghost: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(ghost ? Color.clear : kopi.brand)
                )
                .overlay(
                    Capsule().strokeBorder(ghost ? kopi.line : Color.clear, lineWidth: 1)
                )
                .foregroundStyle(ghost ? kopi.text : kopi.onBrand)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Steam: brand motif + email-first CTA

private struct HouseSteam: View {
    @Environment(\.kopi) private var kopi
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rise = false

    var body: some View {
        HStack(spacing: Space.md) {
            cup
            VStack(alignment: .leading, spacing: 2) {
                Text("Advertise on Kopitiam")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(kopi.text)
                Text("Reach people getting real work done.")
                    .font(.caption)
                    .foregroundStyle(kopi.textSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            VStack(spacing: 6) {
                AdPillButton(title: "Email us", symbol: "envelope.fill") {
                    openURL(AdCopy.mailtoURL)
                }
                AdPillButton(title: "Book a call", symbol: "calendar", ghost: true) {
                    openURL(AdCopy.booking)
                }
            }
            .fixedSize()
        }
        .adCard()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                rise = true
            }
        }
    }

    private var cup: some View {
        ZStack(alignment: .top) {
            // Rising steam wisps (opacity + slight vertical translate only).
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "wind")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(kopi.accent.opacity(rise ? 0.15 : 0.55))
                        .offset(y: rise ? -4 : 2)
                        .animation(reduceMotion ? nil :
                            .easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(Double(i) * 0.25),
                            value: rise)
                }
            }
            .offset(y: -10)
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(kopi.brand)
                .padding(.top, 8)
        }
        .frame(width: 48, height: 48)
    }
}

// MARK: - Tools: cross-promo carousel

private struct HouseTools: View {
    @Environment(\.kopi) private var kopi
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpenTool: (String) -> Void = { _ in }

    private let promos = HouseAdData.toolPromos
    @State private var i = 0
    private let timer = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()

    var body: some View {
        let p = promos[i]
        Button {
            onOpenTool(p.toolID)
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.soon ? "Coming soon" : "Free on Kopitiam")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .kerning(1.0)
                        .foregroundStyle(kopi.accent)
                    Text(p.head)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(kopi.text)
                    Text(p.sub)
                        .font(.caption)
                        .foregroundStyle(kopi.textSoft)
                        .lineLimit(1)
                }
                .id(i) // drive the transition when the slide changes
                .transition(.opacity)
                Spacer(minLength: Space.sm)
                VStack(alignment: .trailing, spacing: 8) {
                    Label(p.soon ? "Preview" : "Open", systemImage: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kopi.accent)
                    HStack(spacing: 4) {
                        ForEach(promos.indices, id: \.self) { n in
                            Circle()
                                .fill(n == i ? kopi.accent : kopi.line)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .adCard()
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                i = (i + 1) % promos.count
            }
        }
    }
}

// MARK: - Sweep: quiet editorial

private struct HouseSweep: View {
    @Environment(\.kopi) private var kopi
    var body: some View {
        Button {
            openURL(AdCopy.mailtoURL)
        } label: {
            HStack(spacing: Space.md) {
                Rectangle()
                    .fill(kopi.accent)
                    .frame(width: 3, height: 40)
                    .clipShape(Capsule())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advertise here")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(kopi.text)
                    Text("Reach people getting real work done.")
                        .font(.caption)
                        .foregroundStyle(kopi.textSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                Label(AdCopy.contactEmail, systemImage: "envelope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kopi.accent)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .adCard()
    }
}
