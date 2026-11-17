import Foundation
import CairnChatDomain

/// What one probe said about one address, port, and path.
///
/// The distinction that matters is between "nothing is there" and "we could not tell". A closed
/// port is an answer; a timeout, a down network, or a Local Network denial is not — and the
/// empty-scan hint has to be honest about which of the two the user is looking at.
enum LANProbeOutcome: Sendable, Equatable {
    /// A model list came back: a server worth offering to the user.
    case modelServer(modelCount: Int)
    /// The port is served and refuses requests without a key — also a server, just not a free one.
    case needsCredential
    /// Something answered, but not at this path. The scan may ask again with the generic path.
    case notAModelServer
    /// Actively refused: no route, nothing listening, connection closed.
    case unreachable
    /// The probe could not be answered at all — timeout, network down, or a denied permission.
    case failure
}

/// The socket question behind the scan, behind a boundary so the scan's policy can be tested on
/// the host without a network: `LANDiscoveryTests` injects a fake and asserts the real rules.
protocol LANProbeTransporting: Sendable {
    func probe(_ probe: ServerProbe) async -> LANProbeOutcome
}

/// Probes over plain http using a short timeout.
///
/// Plaintext is correct here, not an exception to a rule: the scan only ever addresses private
/// IPv4 space, and Apple's ATS "applies only to connections made to public host names" — it gives
/// no protection to an IP address anyway, so there is nothing to switch off.
struct LANDiscoveryTransport: LANProbeTransporting {
    var timeout: TimeInterval = LANDiscoveryPlan.probeTimeoutSeconds

    /// One session for a whole scan instead of one per probe: a sweep issues hundreds of short
    /// requests, and a fresh session each time would spend more time setting up than asking.
    /// Ephemeral, so nothing a probe touched is ever cached to disk.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = LANDiscoveryPlan.probeTimeoutSeconds
        configuration.timeoutIntervalForResource = LANDiscoveryPlan.probeTimeoutSeconds
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpAdditionalHeaders = nil
        return URLSession(configuration: configuration)
    }()

    func probe(_ probe: ServerProbe) async -> LANProbeOutcome {
        guard let url = Self.url(for: probe) else { return .failure }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure }
            switch http.statusCode {
            case 200...299: return classify(body: data, kind: probe.kind)
            case 401, 403: return .needsCredential
            case 404, 405, 501: return .notAModelServer
            default: return .failure
            }
        } catch is CancellationError {
            return .unreachable
        } catch let error as URLError {
            return Self.classify(error)
        } catch {
            return .failure
        }
    }

    private static func url(for probe: ServerProbe) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = probe.host
        components.port = probe.port
        components.path = probe.path
        return components.url
    }

    /// A model list is only a model list if it parses as one, and the answer has to be read in the
    /// dialect the probe asked for. A 200 that parses as nothing is treated as "wrong path", not
    /// as a server: inventing a hit would offer the user a machine that cannot answer a turn.
    private func classify(body: Data, kind: ServerProfileKind) -> LANProbeOutcome {
        let count: Int?
        switch kind {
        case .ollama, .ollamaCloud:
            count = try? OllamaCodec.decodeModelList(body, providerID: "").count
        case .lmStudio:
            count = try? LMStudioCodec.entries(in: body).count
        case .openAICompatible:
            count = try? OpenAICodec.decodeModels(body, providerID: "").count
        }
        guard let count else { return .notAModelServer }
        return .modelServer(modelCount: count)
    }

    /// Refusal means the port is closed; a timeout, a down network, or a request iOS refused to
    /// send says nothing about the port. A denied Local Network permission surfaces as one of the
    /// latter — that is exactly the ambiguity the hint has to name out loud.
    private static func classify(_ error: URLError) -> LANProbeOutcome {
        switch error.code {
        case .cannotConnectToHost, .cannotOpenFile, .networkConnectionLost:
            return .unreachable
        case .timedOut, .notConnectedToInternet, .dataNotAllowed, .cancelled, .cannotFindHost:
            return .failure
        default:
            return .failure
        }
    }
}
