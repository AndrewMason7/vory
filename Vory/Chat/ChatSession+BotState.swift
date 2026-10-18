import VoryCore

extension ChatSession {
    /// Tools that look things up rather than act: Hermes's web_search, the web and browser
    /// tools, and the file and text searches (search_files, grep, glob, find); matched on the
    /// raw name, case-insensitively.
    static func isSearchTool(_ name: String?) -> Bool {
        guard let n = name?.lowercased(), !n.isEmpty else { return false }
        if n.contains("search") || n.contains("grep") || n.contains("glob") { return true }
        return ["web", "browser", "find", "fetch", "web_fetch", "browse", "lookup"].contains(n)
    }

    /// What the chat's bot is doing, for its pose: a card waiting is the ask, the status line
    /// says thinking / tools / writing, a failed open is the error, a reconnect banner the
    /// metronome. Idle otherwise.
    var botState: BotFace.State {
        if !cards.isEmpty { return .awaitingApproval }
        if resumeError != nil, items.isEmpty { return .error }
        if banner?.hasPrefix("Reconnected") == true { return .reconnecting }
        guard isRunning else { return .idle }
        let s = statusLine ?? "Thinking…"
        if s == "Thinking…" || s == "Sending…" || s.hasPrefix("Queued") { return .thinking }
        if s == "Writing…" { return .streaming }
        if s.hasPrefix("Running") || s.hasPrefix("Preparing") {
            // A search (the web, files, text) is the lens; every other tool is the toolbox
            // (decision 4), by the raw tool name, never the prettified line.
            return Self.isSearchTool(currentToolName) ? .searching : .usingTool
        }
        return .working
    }
}
