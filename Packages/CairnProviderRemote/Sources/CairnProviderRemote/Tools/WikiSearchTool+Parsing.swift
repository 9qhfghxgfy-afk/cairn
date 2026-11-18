import Foundation
import CairnChatDomain

extension WikiSearchTool {
    /// `query.search` — the API's own result list. Each entry's `snippet` carries markup (the
    /// search-term highlighting Wikipedia adds), so it is stripped rather than parsed: the words stay
    /// Wikipedia's, and Cairn adds nothing to them.
    static func results(in response: WebHTTPResponse, limit: Int) -> [WebSearchResult] {
        guard let document = WebSearchParsing.document(from: response),
              let query = document.dictionaryValue?["query"],
              case .array(let entries)? = query.dictionaryValue?["search"]
        else { return [] }
        return entries.prefix(max(1, limit)).compactMap { entry in
            guard let fields = entry.dictionaryValue,
                  let title = fields["title"]?.coercedText, !title.isEmpty
            else { return nil }
            return WebSearchResult(
                title: title,
                url: articleURL(for: title),
                snippet: excerpt(fields["snippet"]?.coercedText ?? "")
            )
        }
    }

    /// The article address, built from the title the API named. Spaces and punctuation are percent
    /// escaped the way the wiki's own paths are, so the URL is one `web_fetch` can read.
    static func articleURL(for title: String) -> String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = cleaned.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return articleBase + path
    }

    static func excerpt(_ markup: String) -> String {
        // The extractor, not just an entity pass: Wikipedia's search highlighting arrives as `span`
        // markup, and a tag left in the text would reach the model as though it were prose the article
        // wrote. The words stay Wikipedia's; only the markup around them is removed.
        HTMLTextExtractor.extract(from: markup).replacingOccurrences(of: "\n", with: " ")
    }
}
