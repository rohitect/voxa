import Foundation

struct FileSearchTool: AgentTool {
    let name = "file_search"
    let description = "Search for files on the Mac using Spotlight."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "query",
            type: "string",
            description: "The search query (file name or content keywords)."
        ),
        ToolParameter(
            name: "scope",
            type: "string",
            description: "Where to search.",
            required: false,
            enumValues: ["everywhere", "home", "desktop", "documents"]
        ),
        ToolParameter(
            name: "file_type",
            type: "string",
            description: "File type filter (e.g. 'pdf', 'png', 'swift').",
            required: false
        ),
        ToolParameter(
            name: "limit",
            type: "integer",
            description: "Maximum number of results (default 10).",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let query = arguments["query"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'query'")
        }

        let scope = arguments["scope"] as? String ?? "everywhere"
        let fileType = arguments["file_type"] as? String
        let limit = (arguments["limit"] as? Int) ?? (arguments["limit"] as? Double).map { Int($0) } ?? 10

        let results = try await performSearch(query: query, scope: scope, fileType: fileType, limit: limit)

        if results.isEmpty {
            return .success("No files found matching '\(query)'")
        }

        let output = results.enumerated().map { i, path in
            "\(i + 1). \(path)"
        }.joined(separator: "\n")

        return .success("Found \(results.count) file(s):\n\(output)")
    }

    private func performSearch(query: String, scope: String, fileType: String?, limit: Int) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let metadataQuery = NSMetadataQuery()

            // Build predicate
            var predicates: [NSPredicate] = [
                NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", query)
            ]

            if let fileType = fileType {
                predicates.append(NSPredicate(format: "kMDItemFSName ENDSWITH[c] %@", ".\(fileType)"))
            }

            metadataQuery.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            // Set scope
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            switch scope {
            case "home":
                metadataQuery.searchScopes = [homeDir.path]
            case "desktop":
                metadataQuery.searchScopes = [homeDir.appendingPathComponent("Desktop").path]
            case "documents":
                metadataQuery.searchScopes = [homeDir.appendingPathComponent("Documents").path]
            default:
                metadataQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
            }

            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery,
                queue: .main
            ) { _ in
                metadataQuery.stop()
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }

                var results: [String] = []
                let count = min(metadataQuery.resultCount, limit)
                for i in 0..<count {
                    if let item = metadataQuery.result(at: i) as? NSMetadataItem,
                       let path = item.value(forAttribute: kMDItemPath as String) as? String {
                        results.append(path)
                    }
                }
                continuation.resume(returning: results)
            }

            DispatchQueue.main.async {
                metadataQuery.start()
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if metadataQuery.isGathering {
                    metadataQuery.stop()
                    if let obs = observer {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
