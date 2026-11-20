import Foundation

/// Where a catalog entry's bytes are meant to land, and which name field it is addressed by.
///
/// This is the fact the Download tab turns into copy: "Download to this phone" and "Download to
/// this server" are different sentences with different consequences — one fills the device's own
/// storage, the other asks someone else's machine to fetch over the network. A screen that showed
/// one list without saying which it was would let a person fill a phone with weights it cannot
/// hold, or fill a server with a name it has never heard of.
public enum ModelCatalogOrigin: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    /// An MLX repository this phone can hold, addressed by its Hugging Face repository id.
    case onDevice
    /// A tag in an Ollama server's own library, addressed by that exact tag.
    case ollamaLibrary
    /// A name the person typed that the curated list does not carry.
    case custom

    public var id: String { rawValue }

    /// The word on the source switcher. `Hugging Face` and `Ollama` are the two libraries a person is
    /// actually choosing between, and neither is a destination: an Ollama tag lands on a server that may
    /// well be on this phone's own network.
    public var sourceLabel: String {
        switch self {
        case .onDevice: return "Hugging Face"
        case .ollamaLibrary: return "Ollama"
        case .custom: return "Typed name"
        }
    }

    /// What choosing that source costs, in one line under the switcher.
    public var sourceBlurb: String {
        switch self {
        case .onDevice:
            return "MLX weights for this iPhone, fetched from Hugging Face."
        case .ollamaLibrary:
            return "Tags pulled by an Ollama server you have configured."
        case .custom:
            return "Installed by the exact name you typed."
        }
    }

    /// The destination line under the section title.
    public var destinationText: String {
        switch self {
        case .onDevice: return "Download to this phone"
        case .ollamaLibrary: return "Download to this server"
        case .custom: return "Install by exact name"
        }
    }

    /// True when the bytes land on this device rather than on a server.
    public var landsOnThisPhone: Bool { self == .onDevice }
}
