import Foundation

/// The `(i)` cards for the two optional model tokens, in the Settings group.
///
/// Their own file because `SettingInfoKey+Settings.swift` is already the largest copy file on that
/// screen, and because these two cards answer a question the others do not: what a token is for when
/// every model Cairn lists downloads without one. The answer has to say "you do not need this" before it
/// says what it buys, or the row reads as a wall the person has to get past to use the app.
extension SettingInfoKey {
    static var huggingFaceTokenInfo: SettingInfo {
        SettingInfo(
            title: "Hugging Face Token",
            detail: """
            Optional, and off until you paste one. Every public repository in Cairn's library downloads \
            without a token, and nothing in the app asks for one before it will show you a model. What a \
            token changes is the answer from a repository that asks you to accept its terms before it will \
            hand over the weights: with one, Cairn's request arrives as you, and those files download like \
            any other. It also raises the request ceiling the Hub applies to anonymous traffic, which is \
            what a long list of files or a retry after a dropped connection tends to run into first. \
            The token is kept in the iPhone's own Keychain — never in Cairn's database, never in a \
            settings file, never in a log — and it is sent only to huggingface.co. The storage network \
            that actually serves the bytes is handed a signed link by Hub itself, and Cairn strips the \
            token off that request rather than carrying your credential to a host you did not name. \
            Remove it whenever you like; the public library keeps working exactly as it did.
            """
        )
    }

    static var ollamaRegistryTokenInfo: SettingInfo {
        SettingInfo(
            title: "Ollama Token",
            detail: """
            Optional, and used only for an Ollama endpoint that asks to know who is asking — a hosted \
            registry, or a proxy standing in front of one. A server running on your own network does not \
            need it and does not get it. A profile with a token of its own keeps that token: this one is \
            the fallback for an Ollama profile you added without a credential, so one saved value can \
            serve several servers without a per-server paste. It lives in the iPhone's Keychain, the same \
            place a server's own token lives, and it travels only to the address you typed for that \
            server. Cairn never puts a credential in an ordinary header it read from the settings store, \
            and never writes either one to disk.
            """
        )
    }
}
