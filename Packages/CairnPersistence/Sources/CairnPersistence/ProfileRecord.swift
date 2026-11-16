import Foundation
import SwiftData
import CairnChatDomain

/// On-disk shape of a server profile.
///
/// There is deliberately no token column: the bearer lives in the Keychain under the
/// profile id, so a database dump can never contain a credential, and a bug in this
/// module cannot leak one. Custom headers are plain JSON — they are non-secret by the
/// rule that rejects credential-bearing header names at save time.
@Model
public final class ServerProfileRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var kindRaw: String
    public var baseURLString: String
    public var enabled: Bool
    /// Explicit "this may leave your private network" agreement. Off by default, so a profile
    /// pointing at the public internet is inert until the user turns it on.
    public var publicInternetOptIn: Bool
    /// Display state only: whether a Keychain item exists for this profile. The secret
    /// itself is never stored here.
    public var hasBearerToken: Bool
    public var headersJSON: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        kindRaw: String,
        baseURLString: String,
        enabled: Bool,
        publicInternetOptIn: Bool,
        hasBearerToken: Bool,
        headersJSON: Data?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kindRaw
        self.baseURLString = baseURLString
        self.enabled = enabled
        self.publicInternetOptIn = publicInternetOptIn
        self.hasBearerToken = hasBearerToken
        self.headersJSON = headersJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ServerProfileRecord {
    convenience init(_ profile: ServerProfile) {
        self.init(
            id: profile.id,
            name: profile.name,
            kindRaw: profile.kind.rawValue,
            baseURLString: profile.baseURLString,
            enabled: profile.enabled,
            publicInternetOptIn: profile.publicInternetOptIn,
            hasBearerToken: profile.hasBearerToken,
            // nil stays nil rather than storing an empty "{}" blob.
            headersJSON: profile.customHeaders.isEmpty ? nil : JSONCodec.encode(profile.customHeaders),
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    func toProfile() -> ServerProfile {
        ServerProfile(
            id: id,
            name: name,
            kind: ServerProfileKind(rawValue: kindRaw) ?? .ollama,
            baseURLString: baseURLString,
            customHeaders: JSONCodec.decode([String: String].self, from: headersJSON) ?? [:],
            hasBearerToken: hasBearerToken,
            enabled: enabled,
            publicInternetOptIn: publicInternetOptIn,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
