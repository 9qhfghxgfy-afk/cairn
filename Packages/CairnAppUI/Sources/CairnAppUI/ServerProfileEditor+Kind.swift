import SwiftUI
import CairnChatDomain

/// The kind-aware half of the editor: what switching kind does to the form, and what the kind
/// promises.
///
/// Prefilling is deliberately conservative. A kind knows its own host and port, but it does not
/// know the user's machine — so the URL is only touched when it holds nothing yet, or the shell
/// another kind left behind. Overwriting a typed address because someone changed a dropdown is the
/// kind of thing that makes people stop trusting a form.
extension ServerProfileEditor {
    /// Applies a kind change, keeping anything real the user typed.
    func applyKindChange(_ newKind: ServerProfileKind) {
        kind = newKind
        let backend = newKind.backend
        if isPlaceholderURL(trimmedURL) {
            urlString = backend.prefilledURL
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || isPlaceholderName(trimmedName) {
            name = backend.prefilledName
        }
        // The cloud kind arrives inert: a server on the public internet is never switched on as a
        // side effect of choosing it in a dropdown.
        if backend.offByDefault { enabled = false }
    }

    private func isPlaceholderURL(_ value: String) -> Bool {
        let bare = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if bare.isEmpty { return true }
        if bare == "http://" || bare == "https://" { return true }
        return ServerProfileKind.allCases.contains { $0.backend.prefilledURL == bare }
    }

    private func isPlaceholderName(_ value: String) -> Bool {
        ServerProfileKind.allCases.contains { $0.backend.prefilledName == value }
    }

    /// Where this kind's traffic goes, read from the one declared map rather than restated here.
    var kindEndpointsSummary: String {
        let endpoints = kind.backend.endpoints
        var lines = ["Chat \(endpoints.chat)", "Models \(endpoints.models)"]
        if endpoints.lifecycleWired {
            if let load = endpoints.load { lines.append("Load \(load)") }
            if let unload = endpoints.unload { lines.append("Unload \(unload)") }
            if let download = endpoints.download { lines.append("Download \(download)") }
        }
        return lines.joined(separator: "  ·  ")
    }

    /// The honest footer for the Type picker, including what the kind cannot do yet — which is the
    /// part a user would otherwise discover by pressing a button that fails.
    var kindFooter: String {
        let backend = kind.backend
        var lines: [String] = []
        if let port = backend.defaultPort {
            lines.append("\(kind.displayName) usually listens on port \(port).")
        }
        if backend.expectsToken {
            lines.append("This server refuses requests without a key, so put your key in the token field — it goes to the Keychain, not to the settings database.")
        }
        if backend.offByDefault {
            lines.append("It arrives switched off. Turning it on and allowing requests to leave this device are two separate choices, and both are yours.")
        }
        if !backend.endpoints.lifecycleWired, backend.endpoints.load != nil {
            lines.append("Its load, unload, and download routes are known but not wired yet, so nothing here offers them.")
        }
        lines.append(kind.backend.capabilities.modelPull
            ? "This dialect can also pull and delete models."
            : "This dialect only lists models and answers turns — no pull, no delete.")
        return lines.joined(separator: " ")
    }

    /// A model list is the one action every kind declares; anything narrower would be a button
    /// that cannot work.
    var offersModelListing: Bool {
        kind.backend.capabilities.modelListing
    }
}
