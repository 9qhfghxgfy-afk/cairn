import Foundation

/// What the user picks before the share surface can run.
///
/// There is **no saved "start sharing at launch" flag anywhere in this app**, and that is the
/// point: `ShareSettings` describes a surface the user turns on inside one app session. iOS
/// suspends the phone minutes after it leaves the foreground and the listener dies with it, so a
/// persisted "on" would be a promise the app cannot keep — and a surface that starts by itself at
/// launch, opening a port on a phone that is not in the user's hand, is exactly what this
/// milestone must not do. Off by default is structural, not a default value.
public struct ShareSettings: Sendable, Equatable, Codable {
    /// TCP port to bind. Ollama's own default, so an existing client needs no per-client setup.
    public var port: Int
    /// Which engines this session offers to the network. The served name **is** the engine id, so
    /// a client asking for `cairn-foundation` gets the engine with that id and nothing else.
    public var sharedEngineIDs: [String]

    public init(port: Int = ShareSettings.defaultPort, sharedEngineIDs: [String] = []) {
        self.port = port
        self.sharedEngineIDs = sharedEngineIDs
    }

    /// Ollama's published default port. Nothing on well-known ports below 1024, which a
    /// non-root app cannot bind anyway.
    public static let defaultPort = 11434

    /// The version this surface announces at `/api/version`. Cairn's own name, not an Ollama
    /// version number: a client must not be misled about whose server it reached.
    public static let servedVersion = "cairn-0.1.0"

    public static let `default` = ShareSettings()

    /// Nothing selected means nothing to serve, which is why an empty selection cannot start.
    public var hasSelection: Bool { !sharedEngineIDs.isEmpty }
}

/// The key that keys the surface.
///
/// It lives in the Keychain (`.afterFirstUnlockThisDeviceOnly`) and nowhere else — not in
/// `UserDefaults`, not in a plist, never in a log. `ShareTokenStoring` is the seam the screen holds;
/// the app backs it with the Keychain (`ShareTokenHolding` in `CairnProviderRemote`) and a test backs
/// it with a dictionary.
///
/// Main-actor-isolated, because every vault this app has is: `SecretStoring` is a `@MainActor`
/// protocol, and a holder that was not main-actor-isolated could not reach the Keychain at all
/// without an `await` in the middle of a synchronous screen update. It is also named apart from its
/// concrete holder on purpose — a screen that imports both modules would otherwise read the name
/// `ShareTokenHolding` as ambiguous, and `CairnAppUI` must hold this protocol rather than import the
/// module that owns the Keychain.
@MainActor
public protocol ShareTokenStoring: AnyObject {
    /// The stored token, or nil when none has been set.
    func token() -> String?
    /// Store, or clear when `token` is empty. Returns whether the write held.
    @discardableResult func save(_ token: String) -> Bool
    func clear()
    /// A fresh key from the system generator, replacing the stored one. This is how a key that
    /// leaked into a screenshot, or a laptop the user no longer trusts, is revoked without
    /// uninstalling anything — and it is why the screen offers the act rather than a text field.
    func rotate() -> String
}

public enum ShareToken {
    /// A fresh key: 128 bits from the platform RNG, as lowercase hex.
    ///
    /// Darwin's system RNG is the same one `SecRandomCopy` sits on, so this is not a timestamp or
    /// a UUID-able counter. A generated key means the user never has to invent one, which is the
    /// difference between a keyed surface and an open one.
    public static func generate() -> String {
        (0..<2).map { _ in String(format: "%016llx", UInt64.random(in: 0...UInt64.max)) }.joined()
    }
}
