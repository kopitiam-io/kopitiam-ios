import SwiftUI

// MARK: - App shell: flat, icon-only bottom bar
//
// The shell lives in this file (rather than new files) so the committed
// Kopitiam.xcodeproj keeps building without regenerating it with XcodeGen.

/// The five slots in the bottom bar. `scan` is an action, not a page: it opens
/// the scanner full screen. Labels are never drawn, only read by VoiceOver.
enum AppTab: String, CaseIterable, Identifiable {
    case home, files, scan, tools, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .files: return "Files"
        case .scan: return "Scan"
        case .tools: return "Tools"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .files: return "folder"
        case .scan: return "camera"
        case .tools: return "square.grid.2x2"
        case .settings: return "slider.horizontal.3"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .files: return "folder.fill"
        case .scan: return "camera.fill"
        case .tools: return "square.grid.2x2.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct MainTabView: View {
    @Environment(\.kopi) private var kopi
    @State private var tab: AppTab
    @State private var homePath: [String] = []
    @State private var filesPath: [String] = []
    @State private var toolsPath: [String] = []
    @State private var scanMode: ScanMode?

    init() {
        // Launch argument `-tab files|tools|settings` opens that tab first, for
        // deterministic screenshots. No-op in normal use.
        let args = CommandLine.arguments
        var initial = AppTab.home
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count,
           let t = AppTab(rawValue: args[i + 1]), t != .scan {
            initial = t
        }
        _tab = State(initialValue: initial)
    }

    /// The bar hides once a tool is pushed, so tool screens get the full height.
    private var barHidden: Bool {
        switch tab {
        case .home: return !homePath.isEmpty
        case .files: return !filesPath.isEmpty
        case .tools: return !toolsPath.isEmpty
        case .scan, .settings: return false
        }
    }

    var body: some View {
        ZStack {
            page(.home) {
                HomeTab(path: $homePath, onShowAllTools: { tab = .tools },
                        onShowFiles: { tab = .files }, onScan: { scanMode = $0 })
            }
            page(.files) {
                FilesTab(path: $filesPath, onScan: { scanMode = $0 })
            }
            page(.tools) {
                ToolsTab(path: $toolsPath, onScan: { scanMode = $0 })
            }
            page(.settings) {
                SettingsTab()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !barHidden {
                FlatTabBar(selected: tab, onSelect: select)
            }
        }
        .fullScreenCover(item: $scanMode) { mode in
            ScanHubView(mode: mode)
                .environment(\.kopi, kopi)
        }
        .onAppear { DocumentStore.shared.seedSamplesIfRequested() }
    }

    /// Every tab stays alive (keeping its scroll + navigation state); only the
    /// selected one is visible, tappable and exposed to VoiceOver.
    private func page<Content: View>(_ t: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(tab == t ? 1 : 0)
            .allowsHitTesting(tab == t)
            .accessibilityHidden(tab != t)
    }

    private func select(_ t: AppTab) {
        if t == .scan {
            scanMode = .scan
        } else if t == tab {
            // Tapping the current tab again returns to its root.
            switch t {
            case .home: homePath.removeAll()
            case .files: filesPath.removeAll()
            case .tools: toolsPath.removeAll()
            case .scan, .settings: break
            }
        } else {
            tab = t
        }
    }
}

/// Edge-to-edge bar: five equal icons, a hairline on top, the active one in
/// jade with a small dot under it.
struct FlatTabBar: View {
    @Environment(\.kopi) private var kopi
    let selected: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                let on = t == selected
                Button { onSelect(t) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: on ? t.selectedSymbol : t.symbol)
                            .font(.system(size: 22, weight: .regular))
                            .frame(height: 26)
                        Circle()
                            .fill(on ? kopi.accent : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(on ? kopi.accent : kopi.textSoft)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(kopi.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(kopi.line).frame(height: 1)
        }
    }
}

// MARK: - Routing

/// One place that maps a tool id to its screen.
struct ToolDestination: View {
    let id: String
    var body: some View {
        if id.hasPrefix(Self.docPrefix) {
            DocumentDetailView(documentID: String(id.dropFirst(Self.docPrefix.count)))
        } else {
            tool
        }
    }

    /// Navigation value for a saved document: "doc:<file name>".
    static let docPrefix = "doc:"

    /// Route a tool id, sending the scan tools to the scan hub instead.
    static func open(_ id: String, path: Binding<[String]>, onScan: (ScanMode) -> Void) {
        if let mode = ScanMode(toolID: id) {
            onScan(mode)
        } else {
            path.wrappedValue.append(id)
        }
    }

    @ViewBuilder private var tool: some View {
        switch id {
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
        default:
            if let tool = ToolRegistry.tool(id: id) {
                ComingSoonView(tool: tool)
            }
        }
    }
}

// MARK: - Home tab

private struct QuickItem: Identifiable {
    let id: String     // tool id
    let label: String  // short label under the icon
}

struct HomeTab: View {
    @Environment(\.kopi) private var kopi
    @ObservedObject private var store = DocumentStore.shared
    @Binding var path: [String]
    let onShowAllTools: () -> Void
    let onShowFiles: () -> Void
    let onScan: (ScanMode) -> Void
    @State private var query = ""

    private func open(_ id: String) {
        ToolDestination.open(id, path: $path, onScan: onScan)
    }

    private let quick: [QuickItem] = [
        QuickItem(id: "document", label: "Scan"),
        QuickItem(id: "id-card", label: "ID Cards"),
        QuickItem(id: "ocr", label: "Extract Text"),
        QuickItem(id: "edit", label: "Edit PDF"),
        QuickItem(id: "merge", label: "Merge"),
        QuickItem(id: "compress", label: "Compress"),
        QuickItem(id: "convert", label: "Convert"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        header
                        ToolSearchField(text: $query)
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            LazyVGrid(columns: RoundGrid.columns, spacing: Space.md) {
                                ForEach(quick) { item in
                                    if let tool = ToolRegistry.tool(id: item.id) {
                                        RoundToolButton(tool: tool, label: item.label) {
                                            open(tool.id)
                                        }
                                    }
                                }
                                RoundIconButton(symbol: "square.grid.2x2", label: "All tools",
                                                tint: kopi.brand, action: onShowAllTools)
                            }
                            if !store.documents.isEmpty {
                                recents
                            }
                            AdSlotView(onOpenTool: { id in open(id) })
                                .id("adslot")
                        } else {
                            ToolSearchResults(query: query) { id in open(id) }
                        }
                    }
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.xl)
                }
                .scrollDismissesKeyboard(.immediately)
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
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in ToolDestination(id: id) }
        }
    }

    /// The three newest saved documents.
    private var recents: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("Recents")
                    .font(.headline)
                    .foregroundStyle(kopi.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("View all", action: onShowFiles)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kopi.accent)
            }
            VStack(spacing: 0) {
                ForEach(Array(store.documents.prefix(3).enumerated()), id: \.element.id) { index, doc in
                    if index > 0 {
                        Divider().overlay(kopi.line).padding(.leading, 60)
                    }
                    Button { path.append(ToolDestination.docPrefix + doc.id) } label: {
                        DocumentRow(doc: doc)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.md)
            .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(kopi.line))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            NyonyaTileBand()
                .padding(.bottom, Space.xs)
            Text("Kopitiam")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(kopi.accent)
                .textCase(.uppercase)
                .kerning(1.5)
            (Text("Documents. ").foregroundColor(kopi.text)
             + Text("Done here.").italic().foregroundColor(kopi.accent))
                .font(.system(size: 36, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Space.sm)
    }
}

// MARK: - Tools tab

struct ToolsTab: View {
    @Environment(\.kopi) private var kopi
    @Binding var path: [String]
    let onScan: (ScanMode) -> Void
    @State private var query = ""

    private func open(_ id: String) {
        ToolDestination.open(id, path: $path, onScan: onScan)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    ToolSearchField(text: $query)
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(ToolCategory.allCases) { category in
                            VStack(alignment: .leading, spacing: Space.md) {
                                Text(category.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(kopi.text)
                                    .accessibilityAddTraits(.isHeader)
                                LazyVGrid(columns: RoundGrid.columns, spacing: Space.md) {
                                    ForEach(ToolRegistry.tools(in: category)) { tool in
                                        RoundToolButton(tool: tool, label: tool.title) {
                                            open(tool.id)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        ToolSearchResults(query: query) { id in open(id) }
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xl)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(kopi.bg.ignoresSafeArea())
            .navigationTitle("Tools")
            .navigationDestination(for: String.self) { id in ToolDestination(id: id) }
        }
    }
}

// MARK: - Files tab

/// Saved scans (newest first), plus ways to add more.
struct FilesTab: View {
    @Environment(\.kopi) private var kopi
    @ObservedObject private var store = DocumentStore.shared
    @Binding var path: [String]
    let onScan: (ScanMode) -> Void
    @State private var pendingDelete: SavedDocument?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    FlatRow(symbol: "camera", tint: kopi.accent, title: "Scan a document",
                            subtitle: "Use the camera") { onScan(.scan) }
                    FlatRow(symbol: "doc", tint: kopi.brand, title: "Open a PDF",
                            subtitle: "Edit, sign or highlight it") { path.append("edit") }
                    FlatRow(symbol: "photo.on.rectangle", tint: kopi.accent, title: "Turn photos into a PDF",
                            subtitle: "Pick images from your library") { path.append("convert") }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(kopi.surface)

                Section {
                    if store.documents.isEmpty {
                        Text("Nothing saved yet. Scans you make are kept here, on this phone only.")
                            .font(.subheadline)
                            .foregroundStyle(kopi.textSoft)
                            .listRowBackground(kopi.surface)
                    } else {
                        ForEach(store.documents) { doc in
                            Button { path.append(ToolDestination.docPrefix + doc.id) } label: {
                                DocumentRow(doc: doc)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(kopi.surface)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { pendingDelete = doc } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("On this phone")
                        .foregroundStyle(kopi.textSoft)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(kopi.bg.ignoresSafeArea())
            .navigationTitle("Files")
            .navigationDestination(for: String.self) { id in ToolDestination(id: id) }
            .onAppear { store.reload() }
            .confirmationDialog("Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let doc = pendingDelete { store.delete(doc) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("It will be removed from this phone. This can't be undone.")
            }
        }
    }
}

// MARK: - Settings tab

/// Stored appearance override. "system" follows the phone.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match phone"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsTab: View {
    @Environment(\.kopi) private var kopi
    @AppStorage("appearance") private var appearance: String = AppearanceChoice.system.rawValue

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(choice.title).tag(choice.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(kopi.surface)
                }
                Section("Privacy") {
                    Label("Your documents are processed on this phone and never uploaded. Saved scans stay on this phone.",
                          systemImage: "lock")
                        .foregroundStyle(kopi.text)
                        .listRowBackground(kopi.surface)
                }
                Section("About") {
                    LabeledContent("Version", value: version)
                        .foregroundStyle(kopi.text)
                        .listRowBackground(kopi.surface)
                    Text("Kopitiam is free, always.")
                        .foregroundStyle(kopi.textSoft)
                        .listRowBackground(kopi.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(kopi.bg.ignoresSafeArea())
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Shared shell components

enum RoundGrid {
    static let columns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 4)
}

/// Scale on press without hijacking the scroll gesture.
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .kopiInteractive, value: configuration.isPressed)
    }
}

/// Round tinted icon with a short label underneath (Home + Tools grids).
struct RoundIconButton: View {
    @Environment(\.kopi) private var kopi
    let symbol: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 54, height: 54)
                    .background(tint.opacity(0.14), in: Circle())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(kopi.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

/// Scan + convert tools read jade, PDF tools read kopi brown.
struct RoundToolButton: View {
    @Environment(\.kopi) private var kopi
    let tool: Tool
    let label: String
    let action: () -> Void

    var body: some View {
        RoundIconButton(symbol: tool.symbol, label: label,
                        tint: tool.category == .pdf ? kopi.brand : kopi.accent,
                        action: action)
            .opacity(tool.comingSoon ? 0.6 : 1)
    }
}

/// Flat list row: round icon, title, subtitle, chevron.
struct FlatRow: View {
    @Environment(\.kopi) private var kopi
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(kopi.text)
                    Text(subtitle).font(.footnote).foregroundStyle(kopi.textSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(kopi.textSoft)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ToolSearchField: View {
    @Environment(\.kopi) private var kopi
    @Binding var text: String

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(kopi.textSoft)
                .accessibilityHidden(true)
            TextField("Search tools, like \u{201C}Merge\u{201D}", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(kopi.text)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(kopi.textSoft)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(kopi.line))
    }
}

struct ToolSearchResults: View {
    @Environment(\.kopi) private var kopi
    let query: String
    let onOpen: (String) -> Void

    private var matches: [Tool] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ToolRegistry.all.filter {
            $0.title.lowercased().contains(q) || $0.blurb.lowercased().contains(q)
        }
    }

    var body: some View {
        if matches.isEmpty {
            Text("No tools match \u{201C}\(query)\u{201D}.")
                .font(.subheadline)
                .foregroundStyle(kopi.textSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.lg)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 {
                        Divider().overlay(kopi.line).padding(.leading, 64)
                    }
                    FlatRow(symbol: tool.symbol,
                            tint: tool.category == .pdf ? kopi.brand : kopi.accent,
                            title: tool.title, subtitle: tool.blurb) { onOpen(tool.id) }
                }
            }
            .background(kopi.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(kopi.line))
        }
    }
}

// MARK: - Coming soon

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
