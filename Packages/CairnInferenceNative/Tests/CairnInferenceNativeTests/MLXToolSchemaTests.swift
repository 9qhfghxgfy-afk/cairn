import CairnChatDomain
import Foundation
import Testing

@testable import CairnInferenceNative

/// The mapping layer between Cairn's vocabulary and what an on-device runtime is handed: tool schemas,
/// the message list, and the sampling values.
///
/// Nothing here imports the runtime, deliberately. These are the shapes the runtime receives, and a
/// shape that can only be checked on a machine that links MLX is a shape nobody checks.
struct MLXToolSchemaTests {

    private func tool(
        _ name: String,
        blurb: String,
        properties: [String: ToolParameter] = [:],
        required: [String] = []
    ) -> ToolDefinition {
        ToolDefinition(
            name: name, blurb: blurb,
            parameters: ToolParameterSchema(properties: properties, required: required),
            networkClass: .privateLan
        )
    }

    /// The `function` half of one envelope — the half a chat template renders.
    private func function(_ spec: [String: any Sendable]?) -> [String: any Sendable]? {
        spec?["function"] as? [String: any Sendable]
    }

    private func parameters(_ spec: [String: any Sendable]?) -> [String: any Sendable]? {
        function(spec)?["parameters"] as? [String: any Sendable]
    }

    private func property(
        _ spec: [String: any Sendable]?, _ name: String
    ) -> [String: any Sendable]? {
        (parameters(spec)?["properties"] as? [String: any Sendable])?[name]
            as? [String: any Sendable]
    }

    // MARK: - Tool schemas

    @Test func oneEnvelopePerOfferedToolInTheOrderOffered() {
        let specs = MLXToolSpecs.schemas(for: [
            tool("alpha", blurb: "First."), tool("beta", blurb: "Second."),
        ])
        #expect(specs.count == 2)
        #expect(function(specs.first)?["name"] as? String == "alpha")
        #expect(function(specs.last)?["name"] as? String == "beta")
        #expect(specs.allSatisfy { $0["type"] as? String == "function" })
    }

    @Test func aBlurbReachesTheTemplateOnOneLine() {
        // A template folds the description into a per-tool line, so a newline there breaks the
        // line-per-tool layout several chat formats assume.
        let spec = MLXToolSpecs.schemas(for: [
            tool("lookup", blurb: "Find a city.\n  By name."),
        ]).first
        #expect(function(spec)?["description"] as? String == "Find a city. By name.")
    }

    @Test func parametersAreAnObjectSchemaOfTheDeclaredProperties() {
        let spec = MLXToolSpecs.schemas(for: [
            tool(
                "web_search", blurb: "Search.",
                properties: ["query": ToolParameter(kind: .string, description: "What to look for.")],
                required: ["query"]
            ),
        ]).first
        #expect(parameters(spec)?["type"] as? String == "object")
        #expect(property(spec, "query")?["type"] as? String == "string")
        #expect(property(spec, "query")?["description"] as? String == "What to look for.")
        #expect(parameters(spec)?["required"] as? [String] == ["query"])
    }

    @Test func anArrayCarriesItsItemsAndABlankDescriptionIsOmitted() {
        // A schema without `items` makes some runtimes refuse the tool; a `description` of `""` reads
        // to a model as "this field means nothing".
        let spec = MLXToolSpecs.schemas(for: [
            tool(
                "tag", blurb: "Tag.",
                properties: [
                    "names": ToolParameter(kind: .stringArray),
                    "count": ToolParameter(kind: .integer, description: "  "),
                ]
            ),
        ]).first
        #expect(property(spec, "names")?["type"] as? String == "array")
        let items = property(spec, "names")?["items"] as? [String: any Sendable]
        #expect(items?["type"] as? String == "string")
        #expect(property(spec, "count")?["type"] as? String == "integer")
        #expect(property(spec, "count")?["description"] == nil)
    }

    @Test func aRequiredNameWithNoDeclaredPropertyIsNeverSent() {
        // Cairn's own bug, not something a model can recover from: naming a property the schema
        // never describes. Duplicates collapse because the list is a set of names.
        let spec = MLXToolSpecs.schemas(for: [
            tool(
                "web_search", blurb: "Search.",
                properties: ["query": ToolParameter(kind: .string)],
                required: ["query", "count", "query"]
            ),
        ]).first
        #expect(parameters(spec)?["required"] as? [String] == ["query"])
    }

    @Test func aToolThatTakesNothingStillSendsAnObject() {
        let spec = MLXToolSpecs.schemas(for: [tool("now", blurb: "Current time.")]).first
        #expect(parameters(spec)?["type"] as? String == "object")
        #expect((parameters(spec)?["properties"] as? [String: any Sendable])?.isEmpty == true)
        #expect(parameters(spec)?["required"] as? [String] == [])
    }
}
