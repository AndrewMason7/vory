#if os(iOS)
import SwiftUI
import UIKit

// The phone's page chrome: the leading title every tab root shares (the Chats look, Matt
// 2026-10-12: "add the heading style of the chats page to all the other pages") and Vory's own
// pull-to-refresh, whose wheel sits beside that title. The Mac keeps its window toolbar, its
// Refresh button and its own search field; nothing here is in its target.

/// What a pull has come to, for the wheel beside the title to draw from. One object per page,
/// read only by the wheel: the page's body does not re-run with every frame of a pull.
@MainActor @Observable final class PullRefreshState {
    /// 0 at the edge of the search drawer, 1 at the trigger.
    var progress: CGFloat = 0
    var refreshing = false
    var armed = false
    var dragging = false
    /// A heading's wheel is drawing this state (so the pull adds no wheel of its own).
    var hosted = false
    /// The arc to show: the pull while the finger is down or the trigger has been passed.
    var shown: CGFloat { refreshing ? 0 : (dragging || armed ? progress : 0) }
}

/// The pull's state, handed up to a heading applied outside it (a tab root whose `.reloadable`
/// sits inside the view, `.tabRoot` outside): the heading hosts the wheel either way.
struct PullRefreshRef: Equatable {
    let state: PullRefreshState?
    static func == (a: PullRefreshRef, b: PullRefreshRef) -> Bool { a.state === b.state }
}
struct PullRefreshKey: PreferenceKey {
    static let defaultValue = PullRefreshRef(state: nil)
    static func reduce(value: inout PullRefreshRef, nextValue: () -> PullRefreshRef) {
        let next = nextValue(); if next.state != nil { value = next }
    }
}

/// Pull to refresh, Vory's own rather than `.refreshable`: the system's pull spinner drew inside
/// the search drawer (Matt, 2026-10-10). An over-pull past the drawer fills the wheel beside
/// the title as it comes; at the trigger it arms with a haptic tick, and the refresh runs the
/// moment the finger lifts (never mid-pull, never twice on the bounce), the wheel spinning there
/// for at least a breath before it fades. VoiceOver gets a "Refresh" action.
struct PullRefresh: ViewModifier {
    let action: @MainActor () async -> Void
    /// A page without a `PageHeading` (a pushed page with the system's title): the wheel goes
    /// at the leading edge on its own.
    var ownWheel = false
    @State private var state = PullRefreshState()

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { old, phase in
                state.dragging = phase == .interacting
                if old == .interacting, phase != .interacting {
                    if state.armed, !state.refreshing { state.armed = false; refresh() }
                    else if !state.refreshing { withAnimation(.snappy(duration: 0.2)) { state.progress = 0 } }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in
                // 0 at the top; negative when over-pulled. The wheel fills from the drawer's
                // edge (~24 pt in) to the trigger (~104 pt), so a short pull only shows search.
                // Armed only while the finger is down: the spring-back does not re-arm it.
                guard !state.refreshing else { return }
                let over = max(0, -v)
                if state.dragging { state.progress = min(1, max(0, (over - 24) / 80)) }
                if state.progress >= 1, state.dragging, !state.armed {
                    state.armed = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .accessibilityAction(named: "Refresh") { if !state.refreshing { refresh() } }
            .toolbar {
                if ownWheel, !state.hosted {
                    ToolbarItem(placement: .topBarLeading) { PullRefreshWheel(hosting: false).environment(state) }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
            .environment(state)
            .preference(key: PullRefreshKey.self, value: PullRefreshRef(state: state))
    }

    private func refresh() {
        state.refreshing = true
        Task {
            async let settle: Void = Task.sleep(for: .milliseconds(600))
            await action()
            try? await settle
            withAnimation(.snappy(duration: 0.2)) { state.refreshing = false }
        }
    }
}

/// The pull-to-refresh wheel beside a page's title: an arc that fills as the pull comes, then
/// the spinner while the refresh runs. A fixed slot whenever the page can refresh, so the title
/// never moves as the wheel comes and goes; nothing at all on a page that cannot.
struct PullRefreshWheel: View {
    /// A heading's wheel claims the state (`hosted`), and the pull then adds no wheel of its
    /// own. The pull's own wheel must not claim it: it would remove itself, come back, and
    /// spin the main thread (the first run of testPageHeadings hung 30 s on Home).
    var hosting = true
    /// The state from a pull inside the heading's view (by preference); else the one around it.
    var fromBelow: PullRefreshState? = nil
    @Environment(PullRefreshState.self) private var around: PullRefreshState?
    private var pull: PullRefreshState? { fromBelow ?? around }
    var body: some View {
        ZStack {
            if let pull {
                Circle()
                    .trim(from: 0, to: pull.shown)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(Double(min(1, pull.shown * 1.5)))
                if pull.refreshing { ProgressView().controlSize(.small).transition(.opacity) }
            }
        }
        .frame(width: pull == nil ? 0 : 15, height: 15)
        .padding(.leading, pull == nil ? 0 : 6)
        .animation(.snappy(duration: 0.2), value: pull?.refreshing ?? false)
        .onAppear { if hosting { pull?.hosted = true } }
        .onDisappear { if hosting { pull?.hosted = false } }
        // VoiceOver hears the refresh, not the pull: the arc is decoration, the spinner says so.
        .accessibilityHidden(!(pull?.refreshing ?? false))
        .accessibilityLabel("Refreshing")
    }
}

/// The page's title as a leading toolbar item, in the bar's own type, with the pull-to-refresh
/// wheel after it when the page can refresh. Off on a wide window, where the system title fits.
struct PageHeading: ViewModifier {
    let title: String
    var on = true
    @State private var pullBelow: PullRefreshState?
    func body(content: Content) -> some View {
        if on, !title.isEmpty {
            content
                .onPreferenceChange(PullRefreshKey.self) { pullBelow = $0.state }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        // Its whole width: squeezed by the trailing group on a phone it read "Ch…".
                        HStack(spacing: 0) {
                            Text(title).font(.headline).fixedSize().accessibilityAddTraits(.isHeader)
                            PullRefreshWheel(fromBelow: pullBelow)
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        } else {
            content
        }
    }
}

extension View {
    func pullRefresh(ownWheel: Bool = false, _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(PullRefresh(action: action, ownWheel: ownWheel))
    }
    func pageHeading(_ title: String, on: Bool = true) -> some View { modifier(PageHeading(title: title, on: on)) }
}
#endif
