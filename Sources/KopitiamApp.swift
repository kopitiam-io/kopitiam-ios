import SwiftUI

@main
struct KopitiamApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Resolves the palette for the active color scheme and injects it via Environment.
struct RootView: View {
    @Environment(\.colorScheme) private var scheme

    /// Launch argument `-openEditor` opens straight into the editor with the
    /// on-device sample document loaded. Used for a quick-open shortcut and for
    /// deterministic simulator verification.
    private var opensEditor: Bool {
        CommandLine.arguments.contains("-openEditor")
    }

    /// Launch argument `-openScan` opens straight into the Scan Document screen
    /// for deterministic simulator verification (shows the themed unsupported
    /// state where there is no camera).
    private var opensScan: Bool {
        CommandLine.arguments.contains("-openScan")
    }

    /// Deterministic deep-links for verifying the Group A/B surfaces on the sim.
    private var opensOCR: Bool { CommandLine.arguments.contains("-openOCR") }
    private var opensFilters: Bool { CommandLine.arguments.contains("-openFilters") }
    private var opensConvert: Bool { CommandLine.arguments.contains("-openConvert") }
    private var opensRefine: Bool { CommandLine.arguments.contains("-openRefine") }

    var body: some View {
        Group {
            if opensEditor {
                NavigationStack {
                    EditorView(autoloadSample: true)
                }
            } else if opensScan {
                NavigationStack {
                    ScanDocumentView()
                }
            } else if opensOCR {
                NavigationStack { OCRExtractView(autorun: true) }
            } else if opensFilters {
                NavigationStack { ScanFilterView(autorun: true) }
            } else if opensConvert {
                NavigationStack { ConvertView() }
            } else if opensRefine {
                NavigationStack { PerspectiveRefineView(autorun: true) }
            } else {
                HomeView()
            }
        }
        .environment(\.kopi, KopiTheme.resolve(scheme))
        .tint(KopiTheme.resolve(scheme).accent)
    }
}
