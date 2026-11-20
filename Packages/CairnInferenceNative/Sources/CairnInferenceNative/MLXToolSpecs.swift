import CairnChatDomain
import Foundation

/// Cairn's tool definitions as the schema dictionaries an on-device runtime takes.
///
/// Deliberately free of any MLX import: what a runtime wants is a JSON-Schema envelope, and building
/// it here means the mapping is testable on any host instead of only on a device that links the
/// runtime. The shape is the one `mlx-swift-lm` builds for itself — a `function` object with `name`,
/// `description` and `parameters` — so the model's own chat template sees what it was trained on.
///
/// Cairn executes the tool; the runtime only gets the shapes. Nothing here declares a handler, because
/// a handler inside the runtime would be a second path by which a tool could run without the chat's
/// `Tools` chip, the per-tool toggle or the outbound acknowledgement being consulted.
enum MLXToolSpecs {
    /// One envelope per offered definition, in the order offered.
    ///
    /// The casts are written out rather than left to inference: these dictionaries cross into a
    /// `[String: any Sendable]` type the runtime declares, and an existential upcast that the compiler
    /// has to guess is a compile error waiting for a device build, which is the slowest kind to find.
    static func schemas(for definitions: [ToolDefinition]) -> [[String: any Sendable]] {
        definitions.map { definition in
            [
                "type": "function",
                "function": [
                    "name": definition.name,
                    "description": blurb(definition),
                    "parameters": objectSchema(definition.parameters),
                ] as [String: any Sendable],
            ] as [String: any Sendable]
        }
    }

    /// A blurb on one line: templates fold the description into a prompt, and a multi-line one breaks
    /// the line-per-tool layout several chat formats assume. Runs of whitespace collapse with the line
    /// break, or an indented description arrives at the template padded where its newline used to be.
    static func blurb(_ definition: ToolDefinition) -> String {
        collapseWhitespace(definition.blurb)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var folded = ""
        var lastWasSpace = false
        for character in text {
            if character.isWhitespace {
                if !lastWasSpace { folded.append(" ") }
                lastWasSpace = true
            } else {
                folded.append(character)
                lastWasSpace = false
            }
        }
        return folded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func objectSchema(_ parameters: ToolParameterSchema) -> [String: any Sendable] {
        var properties: [String: any Sendable] = [:]
        for name in parameters.properties.keys.sorted() {
            guard let parameter = parameters.properties[name] else { continue }
            properties[name] = propertySchema(parameter, named: name)
        }
        return [
            "type": "object",
            "properties": properties,
            "required": requiredNames(parameters),
        ] as [String: any Sendable]
    }

    /// Only the names the schema actually describes, each once, in the schema's sorted order. A name the
    /// schema never describes is Cairn's own bug rather than something a model can recover from, and a
    /// name listed twice reads to a template as a parameter the model must supply twice.
    private static func requiredNames(_ parameters: ToolParameterSchema) -> [String] {
        var seen = Set<String>()
        return parameters.required.filter { name in
            guard parameters.properties[name] != nil else { return false }
            return seen.insert(name).inserted
        }
    }

    private static func propertySchema(
        _ parameter: ToolParameter, named name: String
    ) -> [String: any Sendable] {
        var schema = jsonShape(parameter.kind)
        let described = parameter.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !described.isEmpty { schema["description"] = described }
        return schema as [String: any Sendable]
    }

    /// JSON-Schema types, which is what a template's tool block is written against. Cairn's array of
    /// strings carries its `items` because a schema without one makes some runtimes refuse the tool.
    private static func jsonShape(_ kind: ToolParameter.Kind) -> [String: any Sendable] {
        switch kind {
        case .string: return ["type": "string"] as [String: any Sendable]
        case .integer: return ["type": "integer"] as [String: any Sendable]
        case .number: return ["type": "number"] as [String: any Sendable]
        case .boolean: return ["type": "boolean"] as [String: any Sendable]
        case .stringArray:
            return [
                "type": "array",
                "items": ["type": "string"] as [String: any Sendable],
            ] as [String: any Sendable]
        }
    }
}
