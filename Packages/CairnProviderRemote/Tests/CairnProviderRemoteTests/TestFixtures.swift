import Foundation
import CairnChatDomain
@testable import CairnProviderRemote

/// In-memory Keychain stand-in with the same semantics as the real operator, so the token
/// policy (empty value deletes; the uuidString is the only key material) is testable anywhere.
final class FakeKeychainOperator: KeychainOperating, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [KeychainQuery: Data] = [:]

    func set(_ query: KeychainQuery, value: Data) throws {
        lock.lock()
        items[query] = value
        lock.unlock()
    }

    func data(for query: KeychainQuery) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return items[query]
    }

    func remove(_ query: KeychainQuery) throws {
        lock.lock()
        items.removeValue(forKey: query)
        lock.unlock()
    }

    var storedQueries: [KeychainQuery] {
        lock.lock()
        defer { lock.unlock() }
        return Array(items.keys)
    }
}

/// Loopback and documented placeholder hosts only. A real hostname of the user's own network
/// never enters the repo, which is what keeps Scripts/check-hostname.sh green — the only
/// `*.ts.net` value allowed anywhere in this repository is your-host.your-vpn.ts.net.
enum Fixtures {
    static let loopbackOllama = "http://127.0.0.1:11434"
    static let loopbackOpenAI = "http://127.0.0.1:8080"
    static let vpnName = "https://your-host.your-vpn.ts.net"
    static let cloud = "https://api.example.com"

    static func ollama(base: String = loopbackOllama, token: Bool = false) -> ServerProfile {
        ServerProfile(name: "Studio box", kind: .ollama, baseURLString: base, hasBearerToken: token)
    }

    static func openAI(base: String = loopbackOpenAI) -> ServerProfile {
        ServerProfile(name: "Compat server", kind: .openAICompatible, baseURLString: base)
    }

    static func cloud(optIn: Bool) -> ServerProfile {
        ServerProfile(name: "Cloud", kind: .openAICompatible, baseURLString: cloud, publicInternetOptIn: optIn)
    }

    static func request(model: String = "qwen3:8b", thinking: Bool = false) -> GenerationRequest {
        GenerationRequest(
            modelID: model,
            messages: [ChatMessagePayload(role: .user, text: "hi")],
            config: ChatConfig(thinkingEnabled: thinking)
        )
    }
}

/// Line builders so the fixtures read like the wire rather than like escape sequences.
func ollamaLine(thinking: String? = nil, content: String? = nil, done: Bool = false,
                reason: String? = nil, evalCount: Int? = nil,
                promptEvalCount: Int? = nil) -> String {
    var message: [String] = ["\"role\":\"assistant\""]
    if let thinking { message.append("\"thinking\":\"\(thinking)\"") }
    if let content { message.append("\"content\":\"\(content)\"") }
    var fields: [String] = ["\"model\":\"qwen3:8b\"", "\"message\":{\(message.joined(separator: ","))}"]
    fields.append("\"done\":\(done ? "true" : "false")")
    if let reason { fields.append("\"done_reason\":\"\(reason)\"") }
    if let evalCount { fields.append("\"eval_count\":\(evalCount)") }
    if let promptEvalCount { fields.append("\"prompt_eval_count\":\(promptEvalCount)") }
    return "{\(fields.joined(separator: ","))}\n"
}

func sseLine(_ payload: String) -> String { "data: \(payload)\n\n" }

struct Collected: Equatable {
    var thinking = ""
    var content = ""
    var metrics: GenerationMetrics?
}

/// Drains a stream into the parts the assertions care about.
func collect(_ stream: AsyncThrowingStream<StreamChunk, any Error>) async throws -> Collected {
    var out = Collected()
    for try await chunk in stream {
        switch chunk {
        case .thinking(let text): out.thinking += text
        case .content(let text): out.content += text
        case .metrics(let metrics): out.metrics = metrics
        case .toolCall: break
        }
    }
    return out
}

/// Polls a condition instead of sleeping a fixed amount, so slow runners do not flake.
func waitUntil(_ limit: Duration = .seconds(3), _ condition: @escaping @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: limit)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
