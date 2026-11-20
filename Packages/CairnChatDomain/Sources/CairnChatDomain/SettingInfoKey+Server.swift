import Foundation

/// The copy for the server profile editor.
///
/// The two claims that matter here are the transport and the key's home: a machine on your own network is
/// reached over that network in the clear and that is the design, while a public endpoint needs the opt-in and
/// gets a badge. A token is a Keychain value whatever the address is.
extension SettingInfoKey {
    static var serverNameInfo: SettingInfo {
        SettingInfo(
            title: "Server Name",
            detail: """
            The label this server carries in the list, in the model menu, and beside the status dot. Nothing \
            is sent to it or derived from it. Changing it changes only what you read, which is why it is safe \
            to rename a machine you moved to a new address.
            """
        )
    }

    static var serverBackendInfo: SettingInfo {
        SettingInfo(
            title: "Backend Type",
            detail: """
            Which dialect the server speaks: Ollama, LM Studio, or any OpenAI-compatible endpoint. The choice \
            decides which routes Cairn calls, what a model listing gives back, and whether pulling or \
            unloading a model is offered at all — the summary under the field lists the routes for the type \
            you picked, and anything known but not wired says so rather than offering a button that will fail.
            """
        )
    }

    static var serverAddressInfo: SettingInfo {
        SettingInfo(
            title: "Server Address",
            detail: """
            Where the requests go. A server on your own network is reached over that network over plain http — \
            a LAN address, a .local name, or that same private address through your own tunnel — because \
            nothing beyond your own router is part of the plan and Apple's transport security gives no \
            protection to an IP address or an unqualified name anyway. A public-internet address must be https \
            and needs the opt-in below. The badge under the field names which of the two this is.
            """
        )
    }

    static var serverUseEnabledInfo: SettingInfo {
        SettingInfo(
            title: "Use This Server",
            detail: """
            Whether this server is offered to a chat at all. Switching it off keeps the profile and its key \
            and takes the engine out of the menu, so a laptop that is powered down stops appearing as a choice \
            you have to discover is dead.
            """
        )
    }

    static var serverPublicOptInInfo: SettingInfo {
        SettingInfo(
            title: "Allow Requests to Leave This Device",
            detail: """
            The opt-in a public-internet server needs before it can answer. Until it is on the profile is \
            inert: Cairn will not send a prompt, a model list request, or a test to it. With it on, the \
            outbound badge stays up for as long as that traffic can flow, so the state is visible instead of \
            remembered. A server on your own network never asks for this.
            """
        )
    }

    static var serverTokenInfo: SettingInfo {
        SettingInfo(
            title: "API Key",
            detail: """
            The key this server requires, stored in the Keychain for this device only — never in the settings \
            database, never printed, never read back into this field to be shown. Because the field is never \
            filled in, empty means "leave the stored key alone" and the button below it is the only way to \
            remove one. On a plain http address the key crosses your own network unencrypted, which is allowed \
            and said out loud rather than hidden.
            """
        )
    }

    static var serverCustomHeadersInfo: SettingInfo {
        SettingInfo(
            title: "Custom Headers",
            detail: """
            Extra headers sent with every request to this server — a reverse proxy's routing header, say. \
            Their values live in the settings database on the device, so a secret typed here is a secret kept \
            in the clear. Authorization, X-API-Key, Api-Key, Proxy-Authorization and Cookie are refused in \
            these rows and belong in the token field, which is Keychain-backed.
            """
        )
    }
}
