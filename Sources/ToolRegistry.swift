import Foundation

/// Native source of truth for every tool. Adding a tool is one entry here.
struct Tool: Identifiable, Hashable {
    let id: String
    let title: String
    /// SF Symbol name.
    let symbol: String
    let blurb: String
    let category: ToolCategory
    let comingSoon: Bool

    init(id: String, title: String, symbol: String, blurb: String,
         category: ToolCategory, comingSoon: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.blurb = blurb
        self.category = category
        self.comingSoon = comingSoon
    }
}

enum ToolCategory: String, CaseIterable, Identifiable {
    case pdf = "PDF Tools"
    case scan = "Scan"
    case convert = "Convert & Recognize"
    var id: String { rawValue }
}

enum ToolRegistry {
    static let all: [Tool] = [
        // PDF Tools
        Tool(id: "edit", title: "Edit PDF", symbol: "pencil.and.outline",
             blurb: "Add text, draw, highlight, and sign.", category: .pdf),
        Tool(id: "merge", title: "Merge PDF", symbol: "doc.on.doc",
             blurb: "Combine several PDFs into one document.", category: .pdf),
        Tool(id: "split", title: "Split PDF", symbol: "scissors",
             blurb: "Cut a PDF into separate files.", category: .pdf),
        Tool(id: "extract", title: "Extract Pages", symbol: "doc.badge.plus",
             blurb: "Pull out just the pages you need.", category: .pdf),
        Tool(id: "compress", title: "Compress PDF",
             symbol: "arrow.down.right.and.arrow.up.left",
             blurb: "Shrink a PDF to share or upload.", category: .pdf),
        Tool(id: "redact", title: "Redact PDF", symbol: "rectangle.fill",
             blurb: "Black out sensitive text so it is truly removed.",
             category: .pdf),
        // Scan (VisionKit)
        Tool(id: "document", title: "Scan Document", symbol: "doc.viewfinder",
             blurb: "Capture a page straight into a PDF.", category: .scan),
        Tool(id: "id-card", title: "Scan ID Card", symbol: "person.text.rectangle",
             blurb: "Scan both sides of an ID onto one page.", category: .scan),
        Tool(id: "batch", title: "Batch Scan", symbol: "square.stack.3d.up",
             blurb: "Scan many pages in a single session.", category: .scan),
        Tool(id: "filters", title: "Scan Filters", symbol: "wand.and.stars",
             blurb: "Enhance, whiten, grayscale, or B&W a page.", category: .scan),
        Tool(id: "refine", title: "Fix Perspective", symbol: "crop.rotate",
             blurb: "Drag the corners to straighten a photographed page.",
             category: .scan),
        // Convert & Recognize (Group A OCR + Group B convert)
        Tool(id: "ocr", title: "Extract Text (OCR)", symbol: "text.viewfinder",
             blurb: "Read selectable text off scans with Apple Vision.",
             category: .convert),
        Tool(id: "convert", title: "Convert", symbol: "arrow.left.arrow.right",
             blurb: "Image↔PDF, PDF→images, and honest text export.",
             category: .convert),
    ]

    static func tools(in category: ToolCategory) -> [Tool] {
        all.filter { $0.category == category }
    }

    static func tool(id: String) -> Tool? {
        all.first { $0.id == id }
    }
}
