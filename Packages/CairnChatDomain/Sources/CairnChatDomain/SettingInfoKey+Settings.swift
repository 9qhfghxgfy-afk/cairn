import Foundation

/// The copy for the Settings screen and the chat form's non-knob controls.
///
/// Written as computed statics rather than stored ones because a `static let` in an extension of an enum is a
/// global with a namespace on it, and this copy is read a few times per screen at most.
extension SettingInfoKey {
    static var appearanceInfo: SettingInfo {
        SettingInfo(
            title: "Appearance",
            detail: """
            Light and Dark lock the app to that half of the theme you picked; System follows iOS and changes \
            when the system does. Which half is being drawn decides the swatches and the preview card above \
            this picker, so a theme is always judged in the appearance you will actually read it in. Nothing \
            here changes a message, a model choice, or where a request goes.
            """
        )
    }

    static var colorThemeInfo: SettingInfo {
        SettingInfo(
            title: "Colour Theme",
            detail: """
            Recolours Cairn: the canvas, the text, the accent on sliders and switches, and the message \
            bubbles in the preview below. A theme is chosen for readability in the light you are working in, \
            not for looks alone. It is a drawing decision only — it adds no network path, no storage, and no \
            permission, and both halves of every theme exist so the appearance picker above has something to \
            switch between.
            """
        )
    }

    static var defaultConfigurationInfo: SettingInfo {
        SettingInfo(
            title: "Default Configuration",
            detail: """
            The baseline every new chat starts from: your system prompt, the context size, the sampling knobs, \
            and which facts Cairn injects. A chat you already have keeps the settings it was started with, so \
            changing a default never rewrites an answer you are reading. A knob left unset here is left unset \
            on the wire — the server decides that one, which is the difference between a preference and a \
            demand.
            """
        )
    }

    static var injectedContextInfo: SettingInfo {
        SettingInfo(
            title: "System Prompt Context",
            detail: """
            The block Cairn writes ahead of your own system prompt: today's date, the device facts, a summary \
            of what this turn can actually do, and the instructions that tell a model how to use tools and \
            attachments. Each toggle adds one block, in the order shown, and your prompt still goes first and \
            word for word. Switch them all off and nothing is added at all — the model sees only your words.
            """
        )
    }

    static var generationStatsInfo: SettingInfo {
        SettingInfo(
            title: "Generation Statistics",
            detail: """
            Prints elapsed seconds, tokens generated, and tokens per second under each answer. Useful for \
            telling a slow model from a slow network hop. Turning it off hides the numbers and does not stop \
            them being measured, so a chat opened months later still carries how its answer was produced.
            """
        )
    }

    static var webToolsOutboundInfo: SettingInfo {
        SettingInfo(
            title: "Web Tools May Reach the Internet",
            detail: """
            The acknowledgement that lets search, page reading and Wikipedia send a query or an address off \
            this device. It does not run a search by itself — a chat still has to have the tool switched on — \
            and with it off a web question simply fails with the reason named. While traffic is allowed, the \
            outbound badge stays up for as long as it can flow, so the state is visible rather than remembered.
            """
        )
    }

    static var personaInfo: SettingInfo {
        SettingInfo(
            title: "System Prompt",
            detail: """
            Your system prompt: the standing instructions that define the assistant's role, tone and rules for \
            this conversation. It is sent as the first message, word for word, ahead of every block Cairn \
            injects, so a line Cairn adds never re-frames an instruction of yours. Empty means none of yours is \
            sent — and with every injected-context toggle off as well, this conversation has no system message \
            at all.
            """
        )
    }

    static var answerStyleInfo: SettingInfo {
        SettingInfo(
            title: "Answer Style",
            detail: """
            The shape you want answers in: plain prose, Markdown, or as short as possible. It is written into \
            the system block as a request, not enforced by the server, so a small model can still wander and a \
            large one may add structure you did not ask for. None of your own words are rewritten by it.
            """
        )
    }

    static var askForReasoningInfo: SettingInfo {
        SettingInfo(
            title: "Ask for Reasoning",
            detail: """
            Asks this backend for its reasoning and shows the thinking panel only if the backend actually \
            returns any. Cairn never draws a thinking display around an answer it has no reasoning for, and \
            never invents or paraphrases one. On an engine that emits no reasoning trace the switch changes \
            nothing, and the capability line under the composer says so instead of waiting for a surprise.
            """
        )
    }
}
