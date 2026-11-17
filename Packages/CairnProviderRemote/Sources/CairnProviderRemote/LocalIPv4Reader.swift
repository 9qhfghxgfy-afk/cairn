import Foundation
import CairnChatDomain

/// The phone's own private IPv4 addresses, read from the interface table.
///
/// Used for one decision only: which /24 the scan is allowed to look at. Nothing here is stored,
/// returned to the UI, or logged — an address of the user's phone on their own Wi-Fi is personal,
/// so it stays inside this process and inside this file.
enum LocalIPv4Reader {
    /// Interfaces worth scanning, Wi-Fi first: `en0` is the station interface on iPhone and iPad,
    /// and a scan that followed the kernel's order could end up on a cellular or hotspot
    /// interface and look for servers on the carrier's network.
    static func privateAddresses() -> [String] {
        let interfaces = interfaceAddresses()
        let scannable = interfaces.filter { LANDiscoveryPlan.isScannable(host: $0.address) }
        let wifi = scannable.filter { $0.name == "en0" }.map(\.address)
        let others = scannable.filter { $0.name != "en0" }.map(\.address)
        return wifi + others
    }

    /// The address to sweep, or nil when the device is not attached to a private network.
    static func primaryAddress() -> String? { privateAddresses().first }

    private struct InterfaceAddress: Sendable {
        var name: String
        var address: String
    }

    private static func interfaceAddresses() -> [InterfaceAddress] {
        var table: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&table) == 0, let first = table else { return [] }
        defer { freeifaddrs(table) }

        var found: [InterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let record = entry.pointee
            cursor = record.ifa_next
            guard let socketAddress = record.ifa_addr else { continue }
            let raw = UnsafeRawPointer(socketAddress).assumingMemoryBound(to: sockaddr.self)
            guard raw.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard let address = Self.ipv4String(from: socketAddress) else { continue }
            found.append(InterfaceAddress(name: String(cString: record.ifa_name), address: address))
        }
        return found
    }

    private static func ipv4String(from socketAddress: UnsafeMutablePointer<sockaddr>) -> String? {
        var storage = UnsafeRawPointer(socketAddress)
            .assumingMemoryBound(to: sockaddr_in.self)
            .pointee
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let painted = withUnsafePointer(to: &storage.sin_addr) { addressPointer in
            inet_ntop(AF_INET, addressPointer, &buffer, socklen_t(INET_ADDRSTRLEN))
        }
        guard painted != nil else { return nil }
        // `inet_ntop` writes a NUL-terminated C string; stop at the terminator rather than
        // using the deprecated `String(cString:)`.
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}
