import SwiftUI

struct HomeView: View {
    @Environment(\.kopi) private var kopi
    @State private var adTool: Tool?
    private let columns = [
        GridItem(.flexible(), spacing: Space.md),
        GridItem(.flexible(), spacing: Space.md)
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        header
                        ForEach(ToolCategory.allCases) { category in
                            section(for: category)
                        }
                        AdSlotView(onOpenTool: { id in adTool = ToolRegistry.tool(id: id) })
                            .id("adslot")
                    }
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.xl)
                }
                .onAppear {
                    // Launch arg `-scrollToAd` jumps to the ad slot for deterministic
                    // verification screenshots. No-op in normal use.
                    if CommandLine.arguments.contains("-scrollToAd") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { proxy.scrollTo("adslot", anchor: .bottom) }
                        }
                    }
                }
            }
            .background(kopi.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $adTool) { tool in
                destination(for: tool)
            }
        }
    }

    /// Route a tool (used by the ad slot's cross-promo taps).
    @ViewBuilder private func destination(for tool: Tool) -> some View {
        switch tool.id {
        case "edit":     EditorView()
        case "merge":    MergeView()
        case "split":    SplitView()
        case "extract":  ExtractView()
        case "compress": CompressView()
        case "redact":   RedactView()
        case "document": ScanDocumentView()
        case "id-card":  ScanIDCardView()
        case "batch":    ScanBatchView()
        case "filters":  ScanFilterView()
        case "refine":   PerspectiveRefineView()
        case "ocr":      OCRExtractView()
        case "convert":  ConvertView()
        default:         ComingSoonView(tool: tool)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Kopitiam")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(kopi.accent)
                .textCase(.uppercase)
                .kerning(1.5)
            Text("Every PDF tool,\nfree.")
                .font(.system(size: 44, weight: .bold, design: .default))
                .foregroundStyle(kopi.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("A real editor and a full toolkit — right on your iPhone.")
                .font(.title3)
                .foregroundStyle(kopi.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.sm)
    }

    private func section(for category: ToolCategory) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(category.rawValue)
                .font(.title2.weight(.bold))
                .foregroundStyle(kopi.text)
            LazyVGrid(columns: columns, spacing: Space.md) {
                ForEach(ToolRegistry.tools(in: category)) { tool in
                    NavCardLink(tool: tool)
                }
            }
        }
    }
}

/// A card wrapped so it push-navigates on press.
private struct NavCardLink: View {
    let tool: Tool
    @State private var go = false

    var body: some View {
        ToolCard(tool: tool)
            .pressable { go = true }
            .navigationDestination(isPresented: $go) {
                routed
            }
    }

    @ViewBuilder private var routed: some View {
        switch tool.id {
        case "edit":     EditorView()
        case "merge":    MergeView()
        case "split":    SplitView()
        case "extract":  ExtractView()
        case "compress": CompressView()
        case "redact":   RedactView()
        case "document": ScanDocumentView()
        case "id-card":  ScanIDCardView()
        case "batch":    ScanBatchView()
        case "filters":  ScanFilterView()
        case "refine":   PerspectiveRefineView()
        case "ocr":      OCRExtractView()
        case "convert":  ConvertView()
        default:         ComingSoonView(tool: tool)
        }
    }
}

struct ComingSoonView: View {
    let tool: Tool
    @Environment(\.kopi) private var kopi
    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: tool.symbol)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(kopi.brand)
            Text(tool.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(kopi.text)
            Text("Coming soon.")
                .font(.title3)
                .foregroundStyle(kopi.textSoft)
            Text(tool.blurb)
                .font(.body)
                .foregroundStyle(kopi.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(kopi.bg.ignoresSafeArea())
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
