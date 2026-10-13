#if os(iOS)
import SwiftUI
import VoryCore

// Morph prototype, option A proper (BRIEF-1.5-MORPH, `-vory-morph-root`): the top controls of
// the Chats list and of an open chat are drawn here, over the pages and outside every
// NavigationStack, as three persistent glass capsules in ONE GlassEffectContainer. Each capsule
// is drawn at the frame interpolated by `t` between its two measured end states (0 the chat's
// controls, 1 the list's), its contents cross-fading, so a swipe back scrubs the morph with
// the finger (Matt, 2026-10-12: "follow the finger") and a push, a Back button or a release
// animate the same `t`. Reduce Motion: a cross-fade between the two sets, no interpolation.
// Visual apart from Back; nothing here runs without the flag.

/// A control's place in the bar: the leading circle, the middle capsule, the trailing one.
enum MorphSlot: Hashable, CaseIterable { case lead, mid, trail }

/// What a root page keeps in the bar's leading and trailing slots (the middle is its title).
/// A tab switch morphs one page's set into the next; a slot a page does not have fades.
enum TabLead { case botMenu, filesHome }
enum TabTrail { case chatActions, plus(String), filesActions, boardActions, sessionsOptions }
func tabChrome(_ tab: AppModel.AppTab) -> (lead: TabLead?, trail: TabTrail?) {
    switch tab {
    case .chats: (.botMenu, .chatActions)
    case .bots: (nil, .plus("New bot"))
    case .files: (.filesHome, .filesActions)
    case .projects: (nil, .plus("New project"))
    case .cron: (nil, .plus("Add"))
    case .kanban: (nil, .boardActions)
    case .sessions: (nil, .sessionsOptions)
    default: (nil, nil)
    }
}

/// The morph's state: which chat (if any) the chat end state is for, and how far along the
/// list end state the capsules are. Scrubbed by RootView's FullScreenPop handler; animated by
/// the push, the Back button and the release.
@MainActor @Observable final class MorphState {
    static let shared = MorphState()
    var chat: ChatSession?
    /// A page pushed on a tab other than Chats: the title capsule becomes its Back (Matt,
    /// 2026-10-12: "it should morph into the back arrow on all pages and then morph back").
    var pushedTab: AppModel.AppTab?
    /// The tabs other than Chats with a page pushed, kept by their roots' probes whether or not
    /// the bar is up: a tab switch, or the bar's return after the window widened and narrowed
    /// again, finds the right state at once (`showTab`).
    @ObservationIgnored var pushedTabs: Set<AppModel.AppTab> = []
    /// A chat's page is up on Chats without its chat yet (it shows "Opening…"): the bar is away
    /// as over a page pushed on another tab, its title capsule the Back, until the chat comes and
    /// its controls form. Stepped aside there, the bar left the page with no Back and showed
    /// empty glass as the page came in (the frame check's BLANK and LONE runs at a cold push).
    var opening = false
    /// Away from a root page: a chat or a pushed page is up (or on its way).
    var away: Bool { chat != nil || pushedTab != nil || opening }
    /// 0 = the chat's (or the pushed page's) controls, 1 = the root page's. The value the bar
    /// is heading for: the bar draws the animated one (`MorphProgress`), so a transition that
    /// starts mid-flight carries on from where the bar is, with its speed.
    var t: CGFloat = 1
    /// Bumped by every transition that starts: a transition settles (`settleOnRoot`, a pop's or
    /// a release's end) only while it is still the latest. Settled on a timer, an earlier pop's
    /// settle landed inside the next push and took its chat away (Matt on 1.5 (21): in and out
    /// of a chat quickly left the Back circle alone, or no controls at all).
    @ObservationIgnored private var generation = 0
    /// The finger has the pop: `t` follows it and nothing is tappable.
    var scrubbing = false
    /// A swipe back to a tab's root page is under way (its root probe saw it start). Only that
    /// swipe, or a chat's, is the bar's to follow: a swipe from a page three deep back to the one
    /// under it moved the bar to the root's title and left it there, over a page still pushed
    /// (the full-screen pan reports every swipe, whatever its depth).
    @ObservationIgnored var rootPopInFlight = false
    /// The tabs whose page in front keeps its own bar: a form with its own Cancel, Done or Save
    /// (`.pushedPage(keepsOwnBar: true)`), or a page pushed from one. The bar steps aside there,
    /// as it does over a group chat on Chats: the morph Back stood over Edit Gateway's Cancel
    /// (Matt on 1.5 (18): "the formatting is off in the add a gateway"). Kept by the tabs' root
    /// probes; the bar's own state under it is left as it was, so it comes back as it went.
    var ownBarTabs: Set<AppModel.AppTab> = []
    /// A judgement call made while Matt was out: `-vory-ownbar-off` puts the bar's Back over
    /// those pages again, as in (18) and (19).
    static let ownBarOff = ProcessInfo.processInfo.arguments.contains("-vory-ownbar-off")

    /// The Chats stack, handed over by its root (`ChatsStackProbe`): a chat's push and pop there
    /// are followed frame by frame, the page's own slide being the bar's progress. Timed on a
    /// spring of its own, the bar ran apart from the page whenever UIKit turned a transition
    /// around (a quick in and out): both sets half drawn over each other (Matt on 1.5 (21)).
    @ObservationIgnored weak var chatsNav: UINavigationController?
    /// The bar's progress as the page's slide puts it, while a push or a pop is followed. The bar
    /// draws this; `t` keeps where it is heading, which decides the taps.
    var followed: CGFloat?
    @ObservationIgnored private var followLink: CADisplayLink?
    @ObservationIgnored private let followTicker = FollowTicker()
    /// The transition has been seen moving; frames without one before it count down a grace.
    @ObservationIgnored private var followSeen = false
    @ObservationIgnored private var followIdle = 0
    /// `-vory-morph-timed`: the Chats morph on its own spring again, as in 1.5 (22), to compare.
    static let follows = !ProcessInfo.processInfo.arguments.contains("-vory-morph-timed")

    func push(_ c: ChatSession) {
        generation += 1
        // The chat came to a page already in (it was opening): its controls form from the Back.
        if opening, followed == nil, t <= 0 {
            withAnimation(.snappy(duration: 0.22)) { chat = c; opening = false; pushedTab = nil }
            return
        }
        chat = c; pushedTab = nil; opening = false
        // With the page, in the same update. The bar draws every frame from its progress, so the
        // chat's end frames, measured a layout later, are taken up on the way (the first frames
        // are still at the list's). Started a turn later, the list's own search row went with the
        // page while the bar stood still (Matt on 1.5 (21): a partial bar at each push).
        // Heading for the chat already (a push followed since the page opened): nothing to start.
        guard !scrubbing, t > 0 else { return }
        if !follow(to: 0) { toAway() }
    }
    /// A chat's page is coming in on Chats before its chat is there: the bar goes with it.
    func open() {
        guard chat == nil, !scrubbing else { return }
        generation += 1
        opening = true; pushedTab = nil
        guard t > 0 else { return }
        if !follow(to: 0) { toAway() }
    }
    /// The page that came in is a group chat, which keeps its own header: the bar steps aside
    /// (and is at the list's state when it comes back).
    func roomShown() {
        guard chat == nil, opening else { return }
        endFollow()
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { opening = false; t = 1 }
    }
    func pushPage(_ tab: AppModel.AppTab) {
        guard chat == nil else { return }
        generation += 1
        // The page and its morph in one transaction: set apart, the bar went over to the pushed
        // page unanimated and jumped to the Back circle in one frame while the page slid (in (17)
        // too), where the pop morphs back over its slide (Matt on 18: "the reverse of going out").
        if UIAccessibility.isReduceMotionEnabled { withAnimation(.easeInOut(duration: 0.2)) { pushedTab = tab; t = 0 } }
        else { withAnimation(.spring(duration: 0.32, bounce: 0)) { pushedTab = tab; t = 0 } }
    }
    private func toAway() {
        if UIAccessibility.isReduceMotionEnabled { withAnimation(.easeInOut(duration: 0.2)) { t = 0 } }
        // Quick, as the system's own glass morphs are (Matt, 2026-10-12: "too slow").
        else { withAnimation(.spring(duration: 0.32, bounce: 0)) { t = 0 } }
    }
    private func settleOnRoot() { chat = nil; pushedTab = nil; opening = false }
    /// The tab in front changed, or the bar came back: away over that tab's pushed page, at its
    /// root otherwise. With the capsules' own tab move, not the push's morph: a page pushed on
    /// Settings left its Back standing over Chats. A chat belongs to Chats (`open`, the chat up
    /// there): on another tab the bar is that tab's, even while a chat is still closing (a chat
    /// composed from a pushed page closes back onto it), and back on Chats the chat's returns.
    func showTab(_ tab: AppModel.AppTab, chat open: ChatSession?, opening opens: Bool = false) {
        guard !scrubbing else { return }
        endFollow()
        generation += 1
        let g = generation
        if let open {
            // The tab move (0.22 s) like any other tab switch, not the push's 0.32 s morph; on the
            // next turn, so a chat set just now has its end state measured first (push's reason).
            pushedTab = nil
            if chat !== open { chat = open }
            guard t != 0 else { return }
            Perf.stamp("bar: Chats with a chat up, the tab move")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == g, self.chat === open, !self.scrubbing, self.t != 0 else { return }
                withAnimation(.snappy(duration: 0.22)) { self.t = 0 }
            }
            return
        }
        let pushed = pushedTabs.contains(tab)
        // Chats with a chat's page up whose chat is not there yet: away, with its Back.
        let awayHere = pushed || opens
        guard chat != nil || pushedTab != (pushed ? tab : nil) || opening != opens || t != (awayHere ? 0 : 1) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            chat = nil
            opening = opens
            pushedTab = pushed ? tab : nil
            t = awayHere ? 0 : 1
        }
    }
    func scrub(_ fraction: CGFloat) {
        guard away, chat != nil || opening || rootPopInFlight else { return }
        if !scrubbing { generation += 1; endFollow() }
        scrubbing = true
        if UIAccessibility.isReduceMotionEnabled { withAnimation(.easeInOut(duration: 0.2)) { t = fraction >= 0.5 ? 1 : 0 } }
        else { var tr = Transaction(); tr.disablesAnimations = true; withTransaction(tr) { t = fraction } }
    }
    /// The swipe let go: finish to the list (fraction 1) or back to the chat (0) over what is
    /// left of the transition.
    func release(_ fraction: CGFloat, over duration: Double) {
        guard away, chat != nil || opening || rootPopInFlight else { return }
        scrubbing = false
        // With the page: the bar finishing ahead of the slide made the list's controls land
        // before the list (Matt, 2026-10-12: "the nav bar reappears weirdly").
        let d = min(0.4, max(0.18, duration))
        let end: CGFloat = fraction >= 1 ? 1 : 0
        generation += 1
        let g = generation
        // Settled for certain once the transition is over: a trailing event from the second
        // recognizer (the edge gesture and the full-screen pan both drive the pop) could leave
        // `t` or `scrubbing` part-way, which switched the bar's hit testing off (Back after a
        // cancelled swipe did nothing on the phone). Only while this is still the latest
        // transition: a tab switch (showTab) or a new push has put the bar where it belongs.
        withAnimation(.spring(duration: d, bounce: 0), completionCriteria: .logicallyComplete) { t = end } completion: { [weak self] in
            guard let self, self.generation == g else { return }
            self.scrubbing = false
            if end >= 1 { self.t = 1; self.settleOnRoot() } else if self.away { self.t = 0 }
        }
    }
    /// What the bar is doing, for a diagnostic.
    var debugLine: String { "chat=\(chat?.storedID ?? "nil") pushed=\(pushedTab?.rawValue ?? "nil") opening=\(opening) t=\(t) followed=\(followed.map { "\($0)" } ?? "nil") scrubbing=\(scrubbing)" }
    /// A pop that was not a swipe (the Back button): the timed morph.
    func pop() {
        // Once per pop: a page pushed on another tab reported its pop twice (the transition's
        // start and its completion), each starting the morph again.
        guard away, !scrubbing, t < 1 else { return }
        generation += 1
        if follow(to: 1) { return }
        timedPop()
    }
    private func timedPop() {
        let g = generation
        withAnimation(.spring(duration: 0.32, bounce: 0), completionCriteria: .logicallyComplete) { t = 1 } completion: { [weak self] in
            guard let self, self.generation == g, self.t >= 1 else { return }
            self.settleOnRoot()
        }
    }

    // MARK: Following the Chats stack

    /// Follows the Chats stack's push or pop to `end`, if there is one to follow; false otherwise
    /// (a page pushed on another tab, Reduce Motion, no stack), and the bar times its own morph.
    /// The bar heads for `end` at once (taps go to the set that is coming, and a tap can turn it
    /// around); what it draws is the page's place, from where it stands now.
    private func follow(to end: CGFloat) -> Bool {
        guard Self.follows, !UIAccessibility.isReduceMotionEnabled, chat != nil || opening,
              let nav = chatsNav, nav.view.window != nil else { return false }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) {
            if followed == nil { followed = t }
            t = end
        }
        followSeen = false; followIdle = 0
        if followLink == nil {
            followTicker.tick = { [weak self] in self?.followTick() }
            let l = CADisplayLink(target: followTicker, selector: #selector(FollowTicker.fire))
            l.add(to: .main, forMode: .common)
            followLink = l
        }
        return true
    }

    /// Each frame of a followed transition: the bar is where the chat's page is. Once the stack
    /// is still, the bar settles on it; a transition that never came (a path set without one)
    /// gets the timed morph from where the bar stands.
    private func followTick() {
        guard let nav = chatsNav, nav.view.window != nil, !scrubbing, chat != nil || opening else { endFollow(); return }
        if let c = nav.transitionCoordinator {
            // A finger has it: FullScreenPop scrubs.
            guard !c.isInteractive else { endFollow(); return }
            let root = nav.viewControllers.first
            let to = c.viewController(forKey: .to), from = c.viewController(forKey: .from)
            // The chat's page: coming in on a push, going out on a pop. Not before it is laid out
            // in its place (its first frame reads half a width off to the left).
            let rtl = nav.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            guard let page = to !== root ? to : from, page !== root, abs(page.view.frame.minX) < 1,
                  let x = Self.slide(of: page.view, in: nav.view).map({ rtl ? -$0 : $0 }), x > -0.01 else { return }
            followSeen = true; followIdle = 0
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { followed = min(1, max(0, x)) }
            return
        }
        followIdle += 1
        // The push or the pop starts on a turn after the bar heard of it: a few frames' grace.
        guard followSeen || followIdle > 3 else { return }
        let end: CGFloat = nav.viewControllers.count > 1 ? 0 : 1
        let seen = followSeen
        followLink?.invalidate(); followLink = nil
        var tr = Transaction(); tr.disablesAnimations = true
        if seen {
            withTransaction(tr) {
                followed = nil
                t = end
                if end >= 1 { settleOnRoot() }
            }
        } else {
            withTransaction(tr) { t = followed ?? t; followed = nil }
            if end >= 1 { timedPop() } else { toAway() }
        }
    }

    /// Stops following and leaves the bar where it is drawn (`t` takes the place it was at).
    private func endFollow() {
        followLink?.invalidate(); followLink = nil
        guard let f = followed else { return }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { t = f; followed = nil }
    }

    /// Where a page of the stack is on screen, as a fraction of the stack's width (0 in place, 1
    /// off the trailing edge), read through the presentation layers: the transition slides a
    /// wrapper around the page, whose own frame stays at 0.
    static func slide(of v: UIView, in root: UIView) -> CGFloat? {
        var p = CGPoint.zero
        var layer: CALayer? = v.layer
        while let l = layer, l !== root.layer {
            let shown = l.presentation() ?? l
            p = shown.convert(p, to: shown.superlayer)
            layer = l.superlayer
        }
        guard layer != nil else { return nil }
        return p.x / max(1, root.bounds.width)
    }
}

/// The display link's target (it must be an object of Objective-C's).
@MainActor private final class FollowTicker: NSObject {
    var tick: () -> Void = {}
    @objc func fire() { tick() }
}

/// Under the Chats list in its own stack (a phone, the closed Duo): hands the stack to the bar,
/// which follows a chat's push and pop in it frame by frame (`MorphState.follow`).
struct ChatsStackProbe: UIViewRepresentable {
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var r: UIResponder? = self
            while let n = r {
                if let vc = n as? UIViewController { if let nav = vc.navigationController { MorphState.shared.chatsNav = nav }; return }
                r = n.next
            }
        }
    }
    func makeUIView(context: Context) -> Probe {
        let v = Probe()
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        v.accessibilityElementsHidden = true
        return v
    }
    func updateUIView(_ v: Probe, context: Context) {}
}

struct MorphTopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// At the accessibility sizes the bar's type is capped and a long press shows the Large
    /// Content Viewer instead, so the pill's long-press menu steps aside (its items are in …).
    @Environment(\.dynamicTypeSize) private var typeSize
    private var axSize: Bool { typeSize.isAccessibilitySize }
    /// On by default (Matt, 2026-10-12: "the morphing is perfect"); `-vory-morph-off` brings the
    /// shipped chrome back for a comparison.
    static var on: Bool { !ProcessInfo.processInfo.arguments.contains("-vory-morph-off") }
    /// The bar runs where a chat pushes over the list (a phone, the closed Duo's strip): that is
    /// the only place a morph exists. On a wide window (iPad, the open Duo) the list and the
    /// chat stand in their own columns with the shipped chrome, each over its column.
    static func active(_ model: AppModel) -> Bool { on && !model.wideLayout }
    /// The pages swap at once on a tab switch while the bar morphs (Matt's pick, "Instant
    /// swap", 2026-10-12); `-vory-morph-fade` keeps the old cross-fade for a comparison.
    static var cutsPages: Bool { on && !ProcessInfo.processInfo.arguments.contains("-vory-morph-fade") }
    private var state: MorphState { MorphState.shared }
    /// The bots' stored looks, read so the seated face follows a shape change.
    @AppStorage(BotAvatarStore.storageKey) private var avatarsRaw = ""
    /// The list's title capsule: one height on every tab, scaled with the headline.
    @ScaledMetric(relativeTo: .headline) private var titleHeight: CGFloat = 38
    /// The two end states' capsule frames, measured from invisible copies laid out underneath.
    @State private var chatFrames: [MorphSlot: CGRect] = [:]
    /// A pushed page's end state (its Back circle), kept apart from a chat's.
    @State private var pageFrames: [MorphSlot: CGRect] = [:]
    @State private var listFrames: [MorphSlot: CGRect] = [:]
    /// Where a slot last was, so a page without it can fade its capsule out in place.
    @State private var lastListFrames: [MorphSlot: CGRect] = [:]

    /// The bar's progress as drawn this frame (`MorphProgress`): frames, opacities and which
    /// set is mounted follow it, so a push or a pop that starts mid-flight carries on from the
    /// frame on screen. Read from the state's target, every frame started from an end state:
    /// the outgoing set was taken down and the incoming one put up at the start, and a quick
    /// in and out showed both sets half drawn, empty capsules or no controls (Matt on 1.5 (21)).
    @Environment(\.morphProgress) private var drawn
    private var t: CGFloat { state.away ? drawn : 1 }
    /// Where the bar is heading: which set takes taps and which slots are there follow it, so a
    /// tap mid-flight lands on the set that is coming (and can turn the bar around).
    private var target: CGFloat { state.away ? state.t : 1 }
    /// The away state's frames: the chat's, or a pushed page's.
    private var awayFrames: [MorphSlot: CGRect] { state.chat != nil ? chatFrames : pageFrames }
    private var settled: Bool { target <= 0 || target >= 1 }
    /// Where the outgoing set has faded out (`1 - shown * 2.4`) and the incoming one starts: one
    /// control at a time in each capsule, the next one coming in as the last is gone. A gap
    /// between them (the list's set came in from the half) drew empty glass at every switch.
    static let handoff: CGFloat = 1 / 2.4
    /// Reduce Motion: the two sets cross-fade at the halfway point instead of interpolating.
    private var shown: CGFloat { reduceMotion ? (t < 0.5 ? 0 : 1) : t }
    private var shownTarget: CGFloat { reduceMotion ? (target < 0.5 ? 0 : 1) : target }

    var body: some View {
        let _ = Perf.tick("morphbar-body")
        GlassEffectContainer(spacing: 10) {
            ZStack(alignment: .topLeading) {
                // The end states, for their frames only.
                listLayout.opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                if let chat = state.chat { chatLayout(chat).opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
                // A pushed page's end state is the same on every page: laid out always, so the
                // first push already knows where its Back goes.
                pushedLayout.opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                // The capsules that are seen, one per slot, at the frame between the two.
                ForEach(MorphSlot.allCases, id: \.self) { slot in capsule(slot) }
            }
            .coordinateSpace(.named("morph"))
            .padding(.horizontal, 16).padding(.top, 4)
        }
        // The seated face rides above the middle capsule in the chat state: outside the glass
        // container, which composites its glass over anything drawn inside it (the face sat
        // behind its pill, Matt 2026-10-12). Same inset as the measured space.
        .overlay(alignment: .topLeading) {
            if let chat = state.chat, let a = chatFrames[.mid], let b = listFrames[.mid] {
                let mid = lerp(a, b, shown)
                ZStack(alignment: .topLeading) {
                    face(chat, over: mid)
                    // A tap on the seated face does what a tap on the pill does (#339): Bot info,
                    // and the face reacts. Only with the chat at rest.
                    FaceTapArea { openBotInfo(chat) }
                        .frame(width: 44, height: 44)
                        .position(x: mid.midX, y: mid.minY + 10 - 22 + 44 * seatDrop(chat))
                        .allowsHitTesting(shown < 0.02 && !state.scrubbing)
                }
                .padding(.horizontal, 16).padding(.top, 4)
            }
        }
        // The bar's type stops at XXXL, as the system's own bar does: at the accessibility
        // sizes the three capsules no longer fit one row (the actions ran off the right edge
        // and the pill hid the circles, AX3 on the simulator).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Taps reach the controls at rest only; mid-scrub they go nowhere. The bar stays a
        // container for accessibility throughout: hiding and showing it around a scrub made
        // the system fold the Back button into one element the width of the bar (its frame
        // read 370 pt wide after a cancelled swipe, and a tap at its centre hit the pill).
        .allowsHitTesting(settled && !state.scrubbing)
        .accessibilityElement(children: .contain)
        // With a chat shown it is the chat's header for the UI tests (ThreadLayoutUITests
        // measures the thread's first row against the header's bottom).
        .accessibilityIdentifier(state.chat != nil ? "chat.header" : "morph.bar")
        .onChange(of: model.chatsPathOpen) { _, open in
            if open, let c = model.visibleChat { state.push(c) }
            // A chat whose page comes in before its chat (and, for a frame, a group chat, which
            // then steps the bar aside: `roomShown`).
            else if open, model.roomsOnScreen == 0 { state.open() }
            // Also before the push's morph has begun: the pop turns it back (it starts on the
            // next turn), where waiting for it left the chat's controls over the list.
            else if !open, state.chat != nil || state.opening, !state.scrubbing { state.pop() }
        }
        .onChange(of: model.roomsOnScreen) { _, n in if n > 0, model.chatsPathOpen { state.roomShown() } }
        // Initial too: the bar is made afresh when a wide window narrows again.
        .onChange(of: model.selectedTab, initial: true) { _, tab in
            let chats = tab == .chats && model.chatsPathOpen
            state.showTab(tab, chat: chats ? model.visibleChat : nil,
                          opening: chats && model.visibleChat == nil && model.roomsOnScreen == 0)
        }
        .onChange(of: model.visibleChat?.storedID) { _, id in
            // The chat lands a beat after the path opens on a fresh push. And the chat in front
            // can change with the path still open: a Bot Chat opened from a "Messaged X" notice
            // sits over the chat it came from, and back from it that chat is in front again. The
            // bar is the one in front's: kept on the chat underneath, its Back reached that chat
            // and took both pages away (#346, Matt on 1.5 (23): Back went to the list).
            if id != nil, model.chatsPathOpen, let c = model.visibleChat, state.chat !== c { state.push(c) }
        }
    }

    // MARK: The capsules

    @ViewBuilder private func capsule(_ slot: MorphSlot) -> some View {
        // Whether this page (or the chat) has the slot at all: from the page's chrome, not from
        // the measured frames (a slot that went away left a faint empty capsule on Settings).
        let chrome = tabChrome(model.selectedTab)
        let pageHas = slot == .mid || (slot == .lead ? chrome.lead != nil : chrome.trail != nil)
        // Over a group chat on Chats the bar steps aside: that page keeps its own header.
        // Inside the glass container neither a capsule's opacity nor a transition is
        // honoured, so there is no capsule at all there. A page pushed on another tab is an
        // "away" state like a chat: the title capsule becomes its Back and the others go.
        // So does it over a page that keeps its own bar (a form with its Cancel and Save).
        // A chat's page whose chat is not there yet is away, with its Back (`opening`).
        let pushedAway = (model.selectedTab == .chats && model.chatsPathOpen && state.chat == nil && !state.opening) || state.ownBarTabs.contains(model.selectedTab)
        let awayHas = state.chat != nil ? true : (state.pushedTab != nil || state.opening ? slot == .mid : pageHas)
        let present = !pushedAway && (shownTarget < 0.5 ? awayHas : pageHas)
        // Going away (a page pushed on another tab), a slot the away state does not have goes at
        // once, at the push's start: its glass cannot fade inside the container, and shrinking
        // it with the morph left the Bots + standing beside the Back as it formed (Matt on 1.5
        // (17): "the back button leave behind a trail button once in the new window"). It comes
        // back with the usual move; a tab switch still shrinks it where it was.
        let goesAtOnce = !present && state.away
        if pushedAway {
            EmptyView()
        } else if let b = listFrames[slot] ?? lastListFrames[slot] ?? awayFrames[slot] {
            let f = (awayHas ? awayFrames[slot] : nil).map { lerp($0, listFrames[slot] ?? lastListFrames[slot] ?? $0, shown) } ?? b
            ZStack {
                // Only the state that is showing takes taps: the other sits in the stack at
                // opacity 0 and would otherwise cover it (the Back tap went nowhere).
                // Each set is seen alone: the outgoing one is gone by a third of the way and the
                // incoming one arrives past the half, so the capsule carries one control at a
                // time instead of two half-faded over each other (Matt, 2026-10-12, against the
                // Claude app's morph: crisp, each element fading in place).
                // Settled, only the shown set is mounted: a menu's label in the glass kept a
                // ghost of the other set at opacity 0 (the list's bot chip behind Back, the
                // list's icons behind …; Matt, 2026-10-12).
                // These are functions of the frame drawn (`shown`), not of where the bar is
                // heading: from the end values a push or a pop faded both sets across the whole
                // morph, two half-drawn sets over each other, and a quick in and out restarted
                // them from nothing (Matt on 1.5 (21)).
                // Both sets are up for the whole flight, put up and taken down only where their
                // opacity is 0 and with no transition of their own (a fade in on top of the one
                // here would lag it).
                if shown < 1 {
                    if let chat = state.chat { chatContent(slot, chat).opacity(Double(max(0, 1 - shown * 2.4))).allowsHitTesting(shownTarget < 0.5).transition(.identity) }
                    else if let tab = state.pushedTab ?? (state.opening ? .chats : nil), slot == .mid { pageBack(tab).opacity(Double(max(0, 1 - shown * 2.4))).allowsHitTesting(shownTarget < 0.5).transition(.identity) }
                }
                // Keyed by tab, so a tab switch cross-fades one page's control into the next's (at
                // a root page only; going away or back the opacity here does it).
                if shown > 0 { listContent(slot).id(model.selectedTab).transition(state.away ? .identity : .opacity).opacity(Double(max(0, (shown - Self.handoff) * 2.4))).allowsHitTesting(shownTarget >= 0.5 && pageHas) }
            }
            // An absent slot shrinks to nothing where it was: a view's opacity does not fade
            // glass (the + panel taught that), so the capsule also drops its glass there, in
            // the one modifier so its identity holds.
            // Absent on this page: shrunk to nothing where it was (a view's opacity does not
            // fade glass, so the capsule also drops its glass there, in the one modifier).
            .modifier(CapsuleFrame(frame: f, present: present, pull: slot == .mid ? model.pullStates[model.selectedTab] : nil, widen: shown))
            .opacity(present ? 1 : 0)
            .animation(.snappy(duration: 0.22), value: model.selectedTab)
            .animation(goesAtOnce ? nil : .snappy(duration: 0.22), value: present)
        }
    }

    /// How far the chat's face sits into its pill, from the looks read here, so a shape changed on
    /// the bot's card re-seats the face.
    private func seatDrop(_ chat: ChatSession) -> CGFloat {
        BotFace.seatDrop(BotAvatarStore.choice(for: chat.profileName, overrides: BotLookMaps.map(avatarsRaw)).spec(hex: "").shape)
    }

    /// The pill's action: the face reacts and Bot info opens.
    private func openBotInfo(_ chat: ChatSession) {
        BotAmbient.shared.tap(profile: chat.profileName, session: chat.storedID)
        // Bot info covers the face at once: its own face plays the reaction as it lands.
        BotAmbient.shared.markArrival(profile: chat.profileName)
        model.chatRequest = .init(.profile)
    }

    private func face(_ chat: ChatSession, over mid: CGRect) -> some View {
        let drop = seatDrop(chat)
        return BotAvatar(profile: chat.profileName, size: 44, active: chat.isRunning,
                         mood: BotFaceView.Mood(session: chat.storedID, state: chat.botState))
            .scaleEffect(reduceMotion ? 1 : 0.6 + 0.4 * (1 - t))
            // The face lands last: it is seen only once the pill is nearly in place.
            .opacity(Double(max(0, 1 - shown * 2.4)))
            // Seated on the pill by its base, 10 pt over the top edge plus the shape's own seat:
            // a 44-pt face seated this low lets the row sit 18 pt under the bar's top with the
            // head's top at 50 pt, under the Dynamic Island's edge (Matt, 2026-10-12: the
            // buttons were too far down, the head must stay off the island).
            .position(x: mid.midX, y: mid.minY + 10 - 22 + 44 * drop)
            .allowsHitTesting(false)
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    @ViewBuilder private func chatContent(_ slot: MorphSlot, _ chat: ChatSession) -> some View {
        switch slot {
        case .lead:
            Button { model.chatRequest = .init(.back) } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44).contentShape(.circle)
            }
            .buttonStyle(MorphPressStyle(kind: .circle))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Back").accessibilityIdentifier("chat.back").accessibilityAddTraits(.isButton)
            // Activation through accessibility (VoiceOver, XCTest's element tap) did not reach
            // the button on the device; a touch did. The action is offered to both.
            .accessibilityAction { model.chatRequest = .init(.back) }
            .accessibilityShowsLargeContentViewer { Label("Back", systemImage: "chevron.left") }
        case .mid:
            // The face seated over the pill reacts to its tap; a tap on the face itself comes in
            // through FaceTapArea (#339).
            let pill = Button { openBotInfo(chat) } label: { pillText(chat).contentShape(.rect) }
                .buttonStyle(.plain)
            Group {
                if axSize {
                    pill.accessibilityShowsLargeContentViewer { Label(chat.title, systemImage: "person.text.rectangle") }
                } else {
                    pill.contextMenu {
                        Button { model.chatRequest = .init(.rename) } label: { Label("Rename chat", systemImage: "pencil") }
                        Button { model.chatRequest = .init(.profile) } label: { Label("Bot info", systemImage: "person.text.rectangle") }
                    }
                }
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chat info: \(chat.title), \(chat.subtitle)")
                .accessibilityAddTraits([.isButton, .isHeader])
                .accessibilityAction { model.chatRequest = .init(.profile) }
                .accessibilityIdentifier("chat.titlePill")
        case .trail:
            Menu {
                ChatMenuItems(chat: chat, onProfile: { model.chatRequest = .init(.profile) }, onRename: { model.chatRequest = .init(.rename) },
                              onContext: { model.chatRequest = .init(.context) }, onNewChat: { model.chatRequest = .init(.newChat) }, onClose: { model.chatRequest = .init(.close) })
            } label: {
                Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44).contentShape(.circle)
            }
            .menuStyle(.button).buttonStyle(MorphPressStyle(kind: .circle))
            .accessibilityLabel("Chat options")
            .accessibilityShowsLargeContentViewer { Label("Chat options", systemImage: "ellipsis") }
            .accessibilityIdentifier("chat.more")
        }
    }

    @ViewBuilder private func listContent(_ slot: MorphSlot) -> some View {
        let chrome = tabChrome(model.selectedTab)
        switch slot {
        case .lead:
            switch chrome.lead {
            case .botMenu:
                Menu { ChatListProfileItems() } label: {
                    Image(uiImage: BotAvatarImage.cached(profile: model.listChipProfile ?? "?", size: 26, scheme: scheme))
                        .renderingMode(.original).frame(width: 44, height: 44).contentShape(.circle)
                }
                .menuStyle(.button).buttonStyle(MorphPressStyle(kind: .circle))
                .accessibilityLabel("Profile: \(model.listChipProfile ?? "none")")
                .accessibilityShowsLargeContentViewer { Label("Profile", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("chats.profile")
            case .filesHome:
                circleButton("house", label: "Home", id: "files.home") { model.pageRequest = .init(.filesHome) }
            case nil: EmptyView()
            }
        case .mid:
            HStack(spacing: 0) {
                Text(model.selectedTab.title).font(.headline).fixedSize().accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("morph.title")
                PullRefreshWheel(fromBelow: model.pullStates[model.selectedTab])
            }
        case .trail:
            switch chrome.trail {
            case .chatActions: liveActions
            case .plus(let label):
                trailButtons([("plus", label, pageRequestID(for: model.selectedTab), { self.plusRequest(for: model.selectedTab) })])
            case .filesActions:
                trailButtons([(model.filesShowHidden ? "eye" : "eye.slash", model.filesShowHidden ? "Hide hidden files" : "Show hidden files", "files.hidden", { model.pageRequest = .init(.filesToggleHidden) }),
                              ("square.and.arrow.up", "Upload", "files.upload", { model.pageRequest = .init(.filesUpload) })])
            case .boardActions:
                // The board's … menu needs its store (nudge, refresh): the page's own until wired.
                trailButtons([("ellipsis.circle", "Board options", "board.options", {}),
                              ("plus", "New Task", "board.new", { model.pageRequest = .init(.boardNew) })])
            case .sessionsOptions:
                Menu {
                    Button { model.pageRequest = .init(.sessionsAdvanced) } label: { Label("Advanced", systemImage: "internaldrive") }
                } label: { Image(systemName: "gearshape").contentShape(.rect) }
                .menuStyle(.button).buttonStyle(MorphPressStyle(kind: .icon))
                .font(.body.weight(.medium)).foregroundStyle(.tint)
                .padding(.horizontal, 16).frame(height: 44)
                .accessibilityLabel("Options").accessibilityIdentifier("sessions.options")
                .accessibilityShowsLargeContentViewer { Label("Options", systemImage: "gearshape") }
            case nil: EmptyView()
            }
        }
    }

    private func pageRequestID(for tab: AppModel.AppTab) -> String {
        switch tab { case .bots: "bots.newBot"; case .projects: "projects.new"; case .cron: "tasks.add"; default: "\(tab.rawValue).plus" }
    }
    private func plusRequest(for tab: AppModel.AppTab) {
        switch tab {
        case .bots: model.pageRequest = .init(.botsNewBot)
        case .projects: model.pageRequest = .init(.projectsNew)
        case .cron: model.pageRequest = .init(.tasksAdd)
        default: break
        }
    }

    /// A circle button in a leading or trailing slot, with the accessibility it needs.
    private func circleButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.body.weight(.medium)).foregroundStyle(.tint).frame(width: 44, height: 44).contentShape(.circle) }
            .buttonStyle(MorphPressStyle(kind: .circle))
            .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
            .accessibilityIdentifier(id)
    }

    /// A page's trailing buttons, live, with the footprint `trailIcons` is measured with.
    private func trailButtons(_ items: [(symbol: String, label: String, id: String, action: () -> Void)]) -> some View {
        HStack(spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(action: item.action) { Image(systemName: item.symbol).contentShape(.rect) }
                    .buttonStyle(MorphPressStyle(kind: .icon))
                    .accessibilityElement(children: .ignore).accessibilityLabel(item.label).accessibilityAddTraits(.isButton)
                    .accessibilityAction { item.action() }
                    .accessibilityShowsLargeContentViewer { Label(item.label, systemImage: item.symbol) }
                    .accessibilityIdentifier(item.id)
            }
        }
        .font(.body.weight(.medium)).foregroundStyle(.tint)
        .padding(.horizontal, 16).frame(height: 44)
    }

    /// A page's trailing icons (visual in this pass, measured and morphed like the list's).
    private func trailIcons(_ names: [String], label: String) -> some View {
        HStack(spacing: 18) { ForEach(names, id: \.self) { Image(systemName: $0) } }
            .font(.body.weight(.medium)).foregroundStyle(.tint)
            .padding(.horizontal, 16).frame(height: 44)
            .accessibilityLabel(label)
            .accessibilityShowsLargeContentViewer { Label(label, systemImage: names.first ?? "circle") }
    }

    /// The + / sort / filters capsule with its controls live: the same footprint as `actions`,
    /// which the layout is measured with.
    private var liveActions: some View {
        HStack(spacing: 18) {
            Button { model.chatListRequest = .init(.newBot) } label: { Image(systemName: "plus").contentShape(.rect) }
                .buttonStyle(MorphPressStyle(kind: .icon))
                .accessibilityElement(children: .ignore).accessibilityLabel("New bot").accessibilityAddTraits(.isButton)
                .accessibilityAction { model.chatListRequest = .init(.newBot) }
                .accessibilityShowsLargeContentViewer { Label("New bot", systemImage: "plus") }
                .accessibilityIdentifier("chats.newBot")
            Menu { ChatListSortItems() } label: { Image(systemName: "arrow.up.arrow.down").contentShape(.rect) }
                .menuStyle(.button).buttonStyle(MorphPressStyle(kind: .icon))
                .accessibilityLabel("Sort").accessibilityIdentifier("chats.sort")
                .accessibilityShowsLargeContentViewer { Label("Sort", systemImage: "arrow.up.arrow.down") }
            Menu { ChatListFilterItems() } label: { Image(systemName: "line.3.horizontal.decrease.circle").contentShape(.rect) }
                .menuStyle(.button).buttonStyle(MorphPressStyle(kind: .icon))
                .accessibilityLabel("Filters").accessibilityIdentifier("chats.filters")
                .accessibilityShowsLargeContentViewer { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
        }
        .font(.body.weight(.medium)).foregroundStyle(.tint)
        .padding(.horizontal, 16).frame(height: 44)
    }

    // MARK: The end states (laid out, not seen)

    private var listLayout: some View {
        let chrome = tabChrome(model.selectedTab)
        // At least a control's height on every page, so the title capsule sits on the same line
        // whether or not the page has round controls beside it (Matt on 1.5 (17): "the title
        // headings like bot and settings they should all be on the exact same spot"; centred in a
        // row of 44 pt circles, Bots' sat 4 pt below Settings' bare one).
        return HStack(spacing: 10) {
            if chrome.lead != nil { Color.clear.frame(width: 44, height: 44).measured(.lead, into: $listFrames, last: $lastListFrames) }
            // The title alone: the pull's wheel widens the seen capsule itself (CapsuleFrame), so
            // a pull never changes what is measured here. Hidden, not only unseen: at opacity 0 under
            // accessibilityHidden it stayed in the tree as a second title, a "Settings" text over a
            // pushed page's Back.
            Text(model.selectedTab.title).font(.headline).fixedSize().hidden()
            // A set height, not the text's measured one: measured afresh on each tab switch it
            // came out a few points taller for a moment and the capsule breathed (Matt,
            // 2026-10-12: "the height of the bubble from bot to settings seems to change").
            .padding(.horizontal, 12).frame(height: titleHeight)
            .measured(.mid, into: $listFrames, last: $lastListFrames)
            Spacer(minLength: 0)
            switch chrome.trail {
            case .chatActions: actions.measured(.trail, into: $listFrames, last: $lastListFrames)
            case .plus: trailIcons(["plus"], label: "").measured(.trail, into: $listFrames, last: $lastListFrames)
            case .filesActions: trailIcons(["eye.slash", "square.and.arrow.up"], label: "").measured(.trail, into: $listFrames, last: $lastListFrames)
            case .boardActions: trailIcons(["ellipsis.circle", "plus"], label: "").measured(.trail, into: $listFrames, last: $lastListFrames)
            case .sessionsOptions: trailIcons(["gearshape"], label: "").measured(.trail, into: $listFrames, last: $lastListFrames)
            case nil: EmptyView()
            }
        }
        .frame(minHeight: 44)
    }

    /// A pushed page's one control: a Back circle where the chat's Back sits, on the root
    /// row (no face to clear).
    private var pushedLayout: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 44, height: 44).measured(.mid, into: $pageFrames)
            Spacer(minLength: 0)
        }
    }

    /// The pushed page's Back, live: pops its stack one page (the probe under the root does it).
    /// On Chats, a chat's page still opening: its path goes back to the list.
    private func pageBack(_ tab: AppModel.AppTab) -> some View {
        let back = {
            if tab == .chats { if !model.chatPath.isEmpty { model.chatPath.removeLast() } }
            else { model.popOne[tab, default: 0] += 1 }
        }
        return Button { back() } label: {
            Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44).contentShape(.circle)
        }
        .buttonStyle(MorphPressStyle(kind: .circle))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Back").accessibilityIdentifier(tab == .chats ? "chat.back" : "page.back").accessibilityAddTraits(.isButton)
        .accessibilityAction { back() }
        .accessibilityShowsLargeContentViewer { Label("Back", systemImage: "chevron.left") }
    }

    private func chatLayout(_ chat: ChatSession) -> some View {
        // The chat's row sits a little lower than the list's: the seated face rises over the
        // pill's top, and at the list's height it went up under the Dynamic Island.
        HStack(spacing: 12) {
            Color.clear.frame(width: 44, height: 44).measured(.lead, into: $chatFrames)
            Spacer(minLength: 0)
            pillText(chat).measured(.mid, into: $chatFrames)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44).measured(.trail, into: $chatFrames)
        }
        .padding(.top, 18)
    }

    /// The pill's words: the bot's name and the chat's title (or step), as `ChatHeader` shows them.
    private func pillText(_ chat: ChatSession) -> some View {
        let label = chat.runtime.profiles.first { $0.name == chat.profileName }?.label ?? chat.profileName
        let status = chat.isRunning ? (chat.statusLine ?? "Thinking…") : (chat.showsSyncing ? "Syncing…" : chat.title)
        return VStack(spacing: 1) {
            HStack(spacing: 3) {
                Text(label.count > 26 ? String(label.prefix(25)) + "…" : label).font(.caption.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(status.count > 42 ? String(status.prefix(41)) + "…" : status).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 6)
        // Its height is its own; its width gives way, so a long title truncates between the
        // circles instead of pushing the row past the edges (Back sat at x 8 at an
        // accessibility size, HeaderTextSizeUITests).
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Image(systemName: "plus")
            Image(systemName: "arrow.up.arrow.down")
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .font(.body.weight(.medium)).foregroundStyle(.tint)
        .padding(.horizontal, 16).frame(height: 44)
    }
}

/// The bar with its progress drawn: the state's `t`, animated here and handed down each frame
/// (`morphProgress`), so the bar's body draws the frame between, not only the ends. While a
/// chat's push or pop is followed, the page's place instead, frame by frame.
struct MorphBarHost: View {
    var body: some View {
        let s = MorphState.shared
        MorphTopBar().modifier(MorphProgress(t: s.away ? (s.followed ?? s.t) : 1))
    }
}

private struct MorphProgress: ViewModifier, Animatable {
    var t: CGFloat
    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }
    func body(content: Content) -> some View { content.environment(\.morphProgress, t) }
}

extension EnvironmentValues {
    /// The top bar's morph as drawn this frame (1 at a root page, 0 over a chat or pushed page).
    @Entry var morphProgress: CGFloat = 1
}

/// A seen capsule's frame, glass and place. The title's capsule widens here for the pull's wheel
/// (as wide as the wheel and its gap, grown to the right so the title keeps its leading edge),
/// in its own view, so a pull never runs the bar again: with the wheel inside the measured title,
/// every frame of a pull went through the bar's state. It opens in one snappy step, as the
/// wheel's slot does; grown with the finger, the glass resized on every frame and fast pulls
/// hitched on the phone.
private struct CapsuleFrame: ViewModifier {
    let frame: CGRect
    let present: Bool
    var pull: PullRefreshState?
    /// How far the bar is toward the page's own state (1 at the root, 0 over a chat or a pushed
    /// page): the wheel's room goes with the morph. Given in full, a refresh still running as a
    /// chat opened widened its pill to the right, off its words, until the refresh ended.
    var widen: CGFloat = 1
    /// The wheel's side, as PullRefreshWheel's: it grows with the title's type.
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 15
    func body(content: Content) -> some View {
        let open = pull.map { $0.refreshing || $0.shown > 0 } ?? false
        let width = present ? frame.width + (open ? side * 1.4 * widen : 0) : 0
        content
            .frame(width: width, height: present ? frame.height : 0)
            .clipShape(.capsule)
            .glassEffect(present ? .regular : .identity, in: .capsule)
            .position(x: present ? frame.minX + width / 2 : frame.midX, y: frame.midY)
            // With the wheel's own slot: one snappy step open, and closed after the refresh.
            .animation(.snappy(duration: 0.3), value: open)
    }
}

/// The bar's controls pressed (Matt on 1.5 (18): "at touching indication on the top right icons
/// for the chat page"): a soft fill behind the control touched, not its whole shared capsule, and
/// a slight grow, like the system's glass controls, at touch-down; gone on lift or when the finger
/// slides off. A fill, never glass taken to 0 (the glass reference). Reduce Motion: the fill
/// alone. A judgement call made while Matt was out: `-vory-press-style-off` brings back (18)'s
/// plain controls.
struct MorphPressStyle: ButtonStyle {
    enum Kind {
        /// A 44 pt round control (Back, the bot circle, the chat's …): a circle just inside it.
        case circle
        /// An icon in a shared capsule (+, sort, filter): a rounded square around the glyph.
        case icon
    }
    var kind: Kind
    /// The pressed control's size, the one number to change the look by.
    static let pressedScale: CGFloat = 1.05
    static let off = ProcessInfo.processInfo.arguments.contains("-vory-press-style-off")
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !Self.off
        let fill = scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? Self.pressedScale : 1)
            .background {
                Group {
                    switch kind {
                    case .circle: Circle().fill(fill).padding(3)
                    case .icon: RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill).padding(-8)
                    }
                }
                .opacity(pressed ? 1 : 0)
            }
            .animation(.easeOut(duration: pressed ? 0.08 : 0.2), value: pressed)
    }
}

private extension View {
    /// Reports this view's frame in the bar's space under its slot. A change after the first
    /// measurement animates (a tab switch moves and resizes the capsules: the morph); a slot
    /// that goes away leaves its last frame so its capsule can fade out where it was.
    func measured(_ slot: MorphSlot, into frames: Binding<[MorphSlot: CGRect]>, last: Binding<[MorphSlot: CGRect]>? = nil) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("morph")) } action: { f in
            guard frames.wrappedValue[slot] != f else { return }
            if frames.wrappedValue[slot] != nil || last?.wrappedValue[slot] != nil {
                withAnimation(.snappy(duration: 0.22)) { frames.wrappedValue[slot] = f }
            } else {
                frames.wrappedValue[slot] = f
            }
            last?.wrappedValue[slot] = f
        }
        // The frame is not cleared when the view goes: on a tab switch the old view's
        // disappearance landed after the new view's measurement and wiped it, which left the
        // capsule drawn from memory with its hit testing off (the Bots +). Whether a page has
        // the slot comes from its chrome (`tabChrome`), not from the frames.
    }
}
/// The seated face's touch area in a chat (#339): a tap there does what the pill does. A UIKit view
/// with a tap recognizer, out of the accessibility tree (the pill is the element): the pill's own
/// touch shape, stretched over the face, did not reach outside the bar's glass, and a SwiftUI tap
/// gesture here would read to VoiceOver as an unnamed element.
private struct FaceTapArea: UIViewRepresentable {
    var action: () -> Void
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isAccessibilityElement = false
        v.accessibilityElementsHidden = true
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped)))
        return v
    }
    func updateUIView(_ v: UIView, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
#else
import SwiftUI
import VoryCore

/// The Mac keeps its window toolbar and its own chrome: the bar is never on there, so the
/// pages' `if !MorphTopBar.active(model)` guards read as always-shown.
enum MorphTopBar {
    static var on: Bool { false }
    static var cutsPages: Bool { false }
    static func active(_ model: AppModel) -> Bool { false }
}
/// No bar, no chat shown by it: the chat's request handler never matches.
@MainActor final class MorphState {
    static let shared = MorphState()
    var chat: ChatSession? { nil }
}
#endif
