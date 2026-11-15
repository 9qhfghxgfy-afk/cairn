import Foundation

/// Typed, `Sendable` seam over the Keychain, so the token store can be unit-tested on any
/// platform with a fake instead of a real secure enclave.
public struct KeychainQuery: Sendable, Equatable, Hashable {
    public var service: String
    public var account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

public protocol KeychainOperating: Sendable {
    /// Upsert: writes `value`, creating the item when it does not exist yet.
    func set(_ query: KeychainQuery, value: Data) throws
    func data(for query: KeychainQuery) throws -> Data?
    func remove(_ query: KeychainQuery) throws
}

/// Keychain status codes are reported as numbers, never as item contents.
public struct KeychainFailure: Error, Equatable, CustomStringConvertible {
    public var operation: String
    public var status: Int32

    public init(operation: String, status: Int32) {
        self.operation = operation
        self.status = status
    }

    public var description: String { "Keychain \(operation) failed (status \(status))." }
}
