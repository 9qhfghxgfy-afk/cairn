import Foundation

extension RemoteError {
    /// Maps anything thrown by URLSession (or by this module) onto a typed error.
    /// Cancellation and ATS blocks get their own cases so the UI can teach the fix
    /// instead of dumping socket trivia. No URL, host, or header survives here.
    public static func classify(_ error: any Error) -> RemoteError {
        if let typed = error as? RemoteError { return typed }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError { return classify(urlError) }
        return .transport(String(describing: type(of: error)))
    }

    private static func classify(_ urlError: URLError) -> RemoteError {
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .cannotFindHost, .dnsLookupFailed:
            // A name that will not resolve from the phone usually means the VPN tunnel to
            // the network that owns it is not connected. An IP-literal address cannot fail
            // this way, so this is the named-host profile path.
            return .hostNotFound
        case .cannotConnectToHost:
            return .connectionRefused
        case .networkConnectionLost:
            return .transport("connection lost")
        case .notConnectedToInternet:
            return .transport("no network route")
        case .unsupportedURL, .badURL:
            return .invalidURL
        case .appTransportSecurityRequiresSecureConnection:
            return .plainHTTPBlocked
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
             .clientCertificateRejected, .clientCertificateRequired:
            return .tlsFailure
        case .resourceUnavailable:
            return .httpStatus(404, serverMessage: nil)
        default:
            return .transport("URLError \(urlError.code.rawValue)")
        }
    }
}
