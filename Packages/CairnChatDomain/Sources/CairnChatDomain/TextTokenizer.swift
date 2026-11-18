import Foundation

/// Words, as retrieval sees them.
///
/// One tokeniser for both the index and the query, because a query tokenised differently from the
/// documents it is matched against finds nothing and reports that the documents have no answer.
public enum TextTokenizer {
    /// High-frequency English words that carry no topical signal. Small on purpose: a long stop list
    /// starts swallowing the words a user actually typed, and a retrieval miss is worse than a weak
    /// ranking. A stop word still counts toward document length, which is what BM25's normalisation
    /// expects of it.
    public static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can", "did", "do",
        "does", "for", "from", "had", "has", "have", "how", "i", "if", "in", "into", "is",
        "it", "its", "me", "my", "not", "of", "on", "or", "so", "than", "that", "the", "their",
        "them", "then", "there", "these", "they", "this", "to", "was", "we", "were", "what",
        "when", "which", "who", "will", "with", "you", "your",
    ]

    /// Lower-cased alphanumeric tokens, in order, with stop words and one-letter fragments dropped.
    public static func contentTokens(_ text: String) -> [String] {
        rawTokens(text).filter { token in
            token.count > 1 && !stopWords.contains(token)
        }
    }

    /// Every token, including stop words — used for document length, which BM25 normalises on.
    public static func lengthTokens(_ text: String) -> [String] {
        rawTokens(text).filter { $0.count > 1 }
    }

    private static func rawTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                current.append(character)
                continue
            }
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// The words of a question worth indexing, de-duplicated in first-seen order. A repeated word says
    /// the user cared about it once; counting it twice would double its weight in the ranking.
    public static func queryTerms(_ question: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for token in contentTokens(question) where !seen.contains(token) {
            seen.insert(token)
            terms.append(token)
        }
        return terms
    }
}
