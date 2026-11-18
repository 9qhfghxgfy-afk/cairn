import Foundation

/// The wording of every injected block, in one file. Written from scratch for Cairn; the point of
/// keeping it here is that the copy can be reviewed as copy, without a view or an encoder in the
/// way.
///
/// All dates and times are formatted with `en_US_POSIX` in the turn's own timezone, because the
/// surrounding copy is English and because a locale-dependent format would make the assembled block
/// depend on something the user never chose.
extension ContextAssembly {
    static func alwaysBlock(
        for key: ContextKey,
        environment: ContextEnvironment,
        turn: TurnContext,
        format: ResponseFormatPreference
    ) -> String? {
        switch key {
        case .date:
            return "Today is \(formattedDate(environment))."
        case .timeAndTimezone:
            return "The local time is \(formattedTime(environment)) in "
                + "\(environment.clock.timeZoneIdentifier)."
        case .platform:
            return "You are answering inside Cairn, running on \(environment.device.platformName)."
        case .language:
            let code = environment.device.languageCode
            guard !code.isEmpty else { return nil }
            return "The device language is \(code). Answer in the language the user writes in, "
                + "which is not necessarily that one."
        case .localeRegion:
            let code = environment.device.regionCode
            guard !code.isEmpty else { return nil }
            return "The device region is \(code), for units and date conventions only. Nothing else "
                + "about this user is known to you."
        case .capabilitySummary:
            return capabilityLine(turn)
        case .responseFormat:
            return formatLine(format)
        case .toolGuidance, .forceWebFetch, .fileContext, .imageContext:
            return nil
        }
    }

    static func conditionalBlock(for key: ContextKey, turn: TurnContext) -> String? {
        switch key {
        case .toolGuidance:
            let named = turn.toolNames.isEmpty
                ? "Tools are available on this turn."
                : "These tools are available on this turn: \(turn.toolNames.sorted().joined(separator: ", "))."
            return named + " Use one instead of guessing, say which one you used, and never report "
                + "a result a tool did not actually return."
        case .forceWebFetch:
            return "A web search ran for this turn. Open at least one of the result URLs and answer "
                + "from what that page says, citing it. An answer from memory alone is not enough."
        case .fileContext:
            let lead = "The user attached \(turn.fileCount) document\(turn.fileCount == 1 ? "" : "s") "
                + "to this conversation. Ground your answer in them. If they do not cover the "
                + "question, say so rather than filling the gap."
            guard !turn.passages.isEmpty else { return lead }
            let listed = turn.passages
                .map { "[\($0.number)] \($0.documentName): \($0.text)" }
                .joined(separator: "\n\n")
            return lead + "\n\nPassages taken from those documents on this device, most relevant "
                + "first, each marked with its number:\n\n\(listed)\n\nMark every claim that comes "
                + "from a passage with its number, like [2]. Where the passages do not cover "
                + "something, say that instead of supplying it from memory."
        case .imageContext:
            return "The user attached \(turn.imageCount) image(s) to this turn. Say what is "
                + "actually visible in them before drawing any conclusion from them."
        case .date, .timeAndTimezone, .platform, .language, .localeRegion,
             .capabilitySummary, .responseFormat:
            return nil
        }
    }

    private static func capabilityLine(_ turn: TurnContext) -> String? {
        guard let backend = turn.backendLabel, !backend.isEmpty else { return nil }
        var parts: [String] = [backend]
        parts.append(turn.streaming ? "answers arrive as they are produced" : "the answer arrives at once")
        parts.append(turn.thinkingOn ? "reasoning is on" : "reasoning is off")
        if turn.toolsActive {
            parts.append(turn.toolNames.isEmpty
                ? "tools are available"
                : "tools are available: \(turn.toolNames.sorted().joined(separator: ", "))")
        } else {
            parts.append("no tools are available")
        }
        parts.append(turn.visionOn ? "images can be looked at" : "images cannot be looked at")
        if let tokens = turn.contextTokens { parts.append("the context window is \(tokens) tokens") }
        return "What this turn can actually do — \(parts.joined(separator: "; ")). "
            + "Do not claim an ability that is not in this list."
    }

    private static func formatLine(_ format: ResponseFormatPreference) -> String {
        switch format {
        case .plain:
            return "Answer in plain prose. Skip headings and tables unless the question asks "
                + "for them."
        case .markdown:
            return "Answer in Markdown, with code inside fenced blocks."
        case .terse:
            return "Answer in as few words as the question allows. No preamble, no recap."
        }
    }

    private static func formattedDate(_ environment: ContextEnvironment) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone(of: environment)
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: environment.clock.date)
    }

    private static func formattedTime(_ environment: ContextEnvironment) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone(of: environment)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: environment.clock.date)
    }

    /// An unrecognised timezone identifier falls back to UTC rather than to the machine's zone:
    /// a pinned clock in a test must not silently become "whenever this ran".
    private static func timeZone(of environment: ContextEnvironment) -> TimeZone {
        TimeZone(identifier: environment.clock.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }
}
