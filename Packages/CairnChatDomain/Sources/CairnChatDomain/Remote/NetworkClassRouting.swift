import Foundation

/// Classifies where a host actually goes, so every request carries an honest
/// `NetworkClass`. Pure string logic — no DNS, no sockets, no Foundation
/// networking — so it is unit-testable on the macOS host.
public enum NetworkClassRouting: Sendable {
    public static func classify(fromURLString urlString: String) -> NetworkClass {
        guard let components = URLComponents(string: urlString),
              let host = components.host?.lowercased(), !host.isEmpty
        else { return .publicInternet }
        return classify(host: host)
    }

    public static func classify(host rawHost: String) -> NetworkClass {
        // Trim a single trailing dot (FQDN form) and unify bracketed IPv6.
        var host = rawHost.lowercased()
        if host.hasSuffix(".") { host = String(host.dropLast()) }

        // MagicDNS names: <device>.<tailnet>.ts.net (or bare ts.net, which is
        // even broader — also tailnet territory).
        if host == "ts.net" || host.hasSuffix(".ts.net") { return .tailnet }

        // Tailscale CGNAT range 100.64.0.0/10 — a tailnet peer address. Private like
        // any other VPN address. A WireGuard gateway that routes a LAN subnet is not
        // matched here: the phone dials the LAN address itself (e.g. 192.168.x.x), so
        // the RFC 1918 rule below classifies it, whichever side of the tunnel it is on.
        if isIPv4(host, inCGNATRange: true) { return .tailnet }

        if loopback(host) { return .privateLan }
        if isIPv4(host, inRFC1918: true) { return .privateLan }
        if host.hasSuffix(".local") { return .privateLan }
        // Unqualified hostnames (no dots) only resolve on the local network.
        if !host.contains(".") { return .privateLan }

        return .publicInternet
    }

    private static func loopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
            || host.hasPrefix("127.")
    }

    /// - Parameters
    ///   - inRFC1918: 10/8, 172.16/12, 192.168/16
    ///   - inCGNATRange: 100.64/10 (Tailscale)
    private static func isIPv4(_ host: String, inRFC1918: Bool = false, inCGNATRange: Bool = false) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let a = Int(parts[0]), let b = Int(parts[1]),
              let c = Int(parts[2]), let d = Int(parts[3]),
              (0...255).contains(a), (0...255).contains(b),
              (0...255).contains(c), (0...255).contains(d)
        else { return false }

        if inRFC1918 {
            if a == 10 { return true }
            if a == 172 && (16...31).contains(b) { return true }
            if a == 192 && b == 168 { return true }
        }
        if inCGNATRange {
            // 100.64.0.0/10 → second octet 64...127.
            if a == 100 && (64...127).contains(b) { return true }
        }
        return false
    }
}