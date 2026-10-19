#if os(iOS)
import Foundation
import VoryCore

/// The iPhone's turn surface, passed on to a Watch that has the chat open (#387). Every call goes to the inner reporter
/// (the Live Activity) unchanged and in order; a turn starting or ending and its cards changing also tell the Watch
/// (`WatchFeedRules.tellsWatch`), so a Watch chat at rest asks the iPhone nothing. A pure decorator: what the Live
/// Activity shows does not depend on the Watch.
@MainActor
final class WatchTurnRelay: TurnActivityReporting {
    let inner: any TurnActivityReporting
    /// Tells the Watch: WatchSync's sender, which says nothing unless a Watch follows that chat. Tests pass their own.
    private let tell: @MainActor (ChatSession, WatchFeedRules.TurnCall) -> Void

    init(inner: any TurnActivityReporting,
         tell: @escaping @MainActor (ChatSession, WatchFeedRules.TurnCall) -> Void = { WatchSync.shared.chatChanged($0, call: $1) }) {
        self.inner = inner
        self.tell = tell
    }

    func start(for chat: ChatSession) { inner.start(for: chat); pass(chat, .start) }
    func update(for chat: ChatSession, attention: Bool, detail: String?) { inner.update(for: chat, attention: attention, detail: detail); pass(chat, .update) }
    func end(for chat: ChatSession, phase: String) { inner.end(for: chat, phase: phase); pass(chat, .end) }
    func voiceMode(for chat: ChatSession, line: String?) { inner.voiceMode(for: chat, line: line); pass(chat, .voiceMode) }
    func showCards(for chat: ChatSession) { inner.showCards(for: chat); pass(chat, .showCards) }

    private func pass(_ chat: ChatSession, _ call: WatchFeedRules.TurnCall) {
        if WatchFeedRules.tellsWatch(call) { tell(chat, call) }
    }
}
#endif
