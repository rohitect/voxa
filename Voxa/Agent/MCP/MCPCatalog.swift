import Foundation

// MARK: - Catalog Category

enum MCPCatalogCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case desktopAutomation = "Desktop Automation"
    case codeDev = "Code & Dev"
    case data = "Data & APIs"
    case productivity = "Productivity"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .desktopAutomation: return "desktopcomputer"
        case .codeDev: return "chevron.left.forwardslash.chevron.right"
        case .data: return "cylinder.split.1x2"
        case .productivity: return "bolt"
        case .other: return "puzzlepiece"
        }
    }
}

// MARK: - Catalog Tool

struct MCPCatalogTool: Codable, Sendable {
    let name: String
    let description: String
}

// MARK: - Catalog Entry

struct MCPCatalogEntry: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let author: String
    let description: String
    let detailedDescription: String
    let category: MCPCatalogCategory
    let iconName: String
    let repository: String
    let buildCommand: String?
    let transport: MCPTransportType
    let defaultCommand: String?
    let defaultArgs: [String]?
    let requiredPermissions: [String]
    let tools: [MCPCatalogTool]
    let license: String?

    var toolCount: Int { tools.count }
}

// MARK: - Catalog Loader

enum MCPCatalog {

    /// All catalog entries loaded from the bundled mcp-catalog.json.
    static let all: [MCPCatalogEntry] = {
        guard let url = Bundle.main.url(forResource: "mcp-catalog", withExtension: "json") else {
            print("[MCPCatalog] mcp-catalog.json not found in bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([MCPCatalogEntry].self, from: data)
        } catch {
            print("[MCPCatalog] Failed to decode catalog: \(error)")
            return []
        }
    }()

    /// Look up a catalog entry by id.
    static func entry(id: String) -> MCPCatalogEntry? {
        all.first { $0.id == id }
    }

    /// Entries in a given category.
    static func entries(in category: MCPCatalogCategory) -> [MCPCatalogEntry] {
        all.filter { $0.category == category }
    }
}
