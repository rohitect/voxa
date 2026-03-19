import Foundation
import MCP

// MARK: - MCP SDK Type Helpers

enum MCPTypes {

    /// Convert an MCP Tool's inputSchema to our ToolParameter array.
    static func toolParameters(from tool: MCP.Tool) -> [ToolParameter] {
        let schema = tool.inputSchema

        // The inputSchema is a Value type representing JSON Schema
        // Extract properties and required fields
        guard case .object(let schemaDict) = schema else { return [] }

        guard let propertiesValue = schemaDict["properties"],
              case .object(let properties) = propertiesValue else {
            return []
        }

        var requiredNames: Set<String> = []
        if let reqValue = schemaDict["required"], case .array(let reqArray) = reqValue {
            for item in reqArray {
                if case .string(let name) = item {
                    requiredNames.insert(name)
                }
            }
        }

        var params: [ToolParameter] = []
        for (name, value) in properties {
            guard case .object(let propDict) = value else { continue }

            let type: String
            if let typeValue = propDict["type"], case .string(let t) = typeValue {
                type = t
            } else {
                type = "string"
            }

            let description: String
            if let descValue = propDict["description"], case .string(let d) = descValue {
                description = d
            } else {
                description = ""
            }

            var enumValues: [String]?
            if let enumValue = propDict["enum"], case .array(let enumArray) = enumValue {
                enumValues = enumArray.compactMap { val in
                    if case .string(let s) = val { return s }
                    return nil
                }
            }

            params.append(ToolParameter(
                name: name,
                type: type,
                description: description,
                required: requiredNames.contains(name),
                enumValues: enumValues
            ))
        }

        return params.sorted { $0.name < $1.name }
    }

    /// Convert `[String: Any]` arguments dict to MCP SDK's `[String: Value]`.
    static func convertArguments(_ arguments: [String: Any]) -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, val) in arguments {
            result[key] = anyToValue(val)
        }
        return result
    }

    /// Extract text content from MCP callTool result.
    static func extractText(from content: [Tool.Content]) -> String {
        let parts: [String] = content.compactMap { item in
            switch item {
            case .text(let text):
                return text
            case .image:
                return "[image content]"
            case .resource:
                return "[resource content]"
            case .audio:
                return "[audio content]"
            case .resourceLink:
                return "[resource link]"
            @unknown default:
                return "[unknown content]"
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Private

    private static func anyToValue(_ val: Any) -> Value {
        switch val {
        case let s as String:
            return .string(s)
        case let n as Int:
            return .int(n)
        case let n as Double:
            return .double(n)
        case let b as Bool:
            return .bool(b)
        case let arr as [Any]:
            return .array(arr.map { anyToValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { anyToValue($0) })
        default:
            return .string(String(describing: val))
        }
    }
}
