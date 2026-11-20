import Foundation

/// Which library the Download tab opens on, and whether the server in front of the user can pull.
///
/// Two names for the same pair of lists exist for a reason. `ModelCatalogOrigin` says where the bytes
/// land, which is what a button has to promise; this says where the **names** come from, which is what
/// a switcher has to be legible as. A person choosing between `Hugging Face` and `Ollama` is choosing a
/// library, and the difference between the two is not a destination — an Ollama tag can be pulled onto a
/// server that is on the same network as this phone.
public enum ModelCatalogOpening {
    /// The source to open on, from the server that opened the Models screen.
    ///
    /// No server means On-Device, so the phone's own MLX library leads. Any remote server leads on the
    /// Ollama library instead, including a server that speaks only the OpenAI shape: the Download tab is
    /// never empty while it is being looked at, and a name the open server cannot install is still worth
    /// reading, because the same screen says which server can take it.
    public static func origin(forKind kind: ServerProfileKind?) -> ModelCatalogOrigin {
        guard kind != nil else { return .onDevice }
        return .ollamaLibrary
    }

    /// True when the server behind `kind` takes a pull for an Ollama tag.
    ///
    /// A pull is a request to install, not a request to list, so it belongs to the two kinds that
    /// document `/api/pull`. LM Studio and an OpenAI-compatible server can be asked for their names, but
    /// asking them to fetch a tag they have no endpoint for would be a request that cannot succeed.
    public static func pullsDirectly(fromKind kind: ServerProfileKind?) -> Bool {
        switch kind {
        case .ollama, .ollamaCloud: return true
        case .lmStudio, .openAICompatible, nil: return false
        }
    }
}
