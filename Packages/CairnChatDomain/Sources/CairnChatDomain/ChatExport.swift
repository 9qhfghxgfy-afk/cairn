import Foundation

/// Writes a chat out as a `.cairn` file and reads one back.
///
/// JSON, pretty-printed with sorted keys and ISO-8601 timestamps: a file a user can open in a text
/// editor, diff by hand, and still recognise as their own conversation. Sorting the keys means the same
/// chat exported twice in the same state produces the same bytes, so "did my data change?" is a question
/// a diff can answer.
///
/// Nothing here reaches a network, a file URL or a security object. `FileExporter` in the app layer owns
/// the panel and the write; this is the bytes and the checks, which is what makes both of them testable
/// without a simulator.
public enum ChatExport {

    /// One chat, with its own messages. Extra nodes are ignored rather than smuggled in.
    public static func bundle(
        conversation: Conversation,
        nodes: [ChatNode],
        exportedAt: Date = Date()
    ) -> ChatExportBundle {
        bundle(conversations: [conversation], nodes: nodes, exportedAt: exportedAt)
    }

    /// Every chat passed in, each keeping its tree. Nodes that belong to a chat not in the list are
    /// dropped — a file must not carry a message whose conversation it does not contain.
    public static func bundle(
        conversations: [Conversation],
        nodes: [ChatNode],
        exportedAt: Date = Date()
    ) -> ChatExportBundle {
        let wanted = Set(conversations.map(\.id))
        return ChatExportBundle(
            exportedAt: exportedAt,
            chats: conversations.map { ExportedChat($0) },
            nodes: nodes.filter { wanted.contains($0.conversationID) }.map { ExportedNode($0) }
        )
    }

    /// The bytes to hand to a file writer. Throws only when a value cannot be represented as JSON, which
    /// for these types means a `Date` outside the encodable range.
    public static func data(
        conversations: [Conversation],
        nodes: [ChatNode],
        exportedAt: Date = Date()
    ) throws -> Data {
        try encoder().encode(bundle(conversations: conversations, nodes: nodes, exportedAt: exportedAt))
    }

    /// Reads a file, checking the marker and version **before** anything is decoded into the app.
    public static func decode(_ data: Data) throws -> ChatExportBundle {
        let header = try Self.decodedHeader(data)
        guard header.format == ChatExportBundle.formatMarker else {
            throw ChatExportIssue.foreignFormat(header.format)
        }
        guard header.version <= ChatExportBundle.currentVersion else {
            throw ChatExportIssue.newerVersion(header.version)
        }
        guard header.version >= 1 else {
            throw ChatExportIssue.unsupportedVersion(header.version)
        }
        do {
            return try decoder().decode(ChatExportBundle.self, from: data)
        } catch {
            throw ChatExportIssue.unreadable(String(describing: type(of: error)))
        }
    }

    /// The two keys that decide whether the rest of the file is worth parsing at all.
    private static func decodedHeader(_ data: Data) throws -> (format: String, version: Int) {
        struct Header: Decodable { let format: String; let version: Int }
        do {
            let header = try decoder().decode(Header.self, from: data)
            return (header.format, header.version)
        } catch {
            throw ChatExportIssue.unreadable("it has no format marker to read")
        }
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
