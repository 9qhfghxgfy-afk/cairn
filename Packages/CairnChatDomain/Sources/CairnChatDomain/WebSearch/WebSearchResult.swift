import Foundation

/// One search result, in the shape every provider reduces to.
///
/// The three providers answer in three different documents — DuckDuckGo's HTML page, SearXNG's JSON,
/// Ollama Cloud's JSON — and normalising them here is what lets the tool's output, the card and the
/// tests speak one format. `snippet` is what the provider itself published; Cairn does not summarise a
/// page it has not read.
public struct WebSearchResult: Sendable, Equatable, Codable {
    public var title: String
    public var url: String
    public var snippet: String

    public init(title: String, url: String, snippet: String = "") {
        self.title = title
        self.url = url
        self.snippet = snippet
    }

    public var isUsable: Bool { !url.isEmpty }

    /// The lines a model reads, numbered so it can cite one and hand its URL to `web_fetch`.
    public static func render(_ results: [WebSearchResult]) -> String {
        let usable = results.filter(\.isUsable)
        guard !usable.isEmpty else { return "" }
        return usable.enumerated().map { index, result in
            var line = "\(index + 1). \(result.title.isEmpty ? result.url : result.title)\n   \(result.url)"
            let snippet = result.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty { line += "\n   \(snippet)" }
            return line
        }.joined(separator: "\n\n")
    }
}
