import SwiftUI
import VoryCore

/// Our own tab bar, drawn to the system Liquid Glass tab bar on iOS 27: a glass capsule of
/// equal-width, icon-only tabs, a clear glass lens over the selected one (its label shows under
/// the icon only there), and a detached glass compose circle the full height of the capsule.
/// The system TabView cannot draw this on the current iOS (a search-role tab renders inline),
/// so the tab pages sit in a ZStack behind it instead.
///
/// Measurements from a UITabBar dump on iOS 27 / iPhone 17 Pro: capsule 62 pt with 4 pt inset
/// around 54 pt slots, 21 pt side margins, the bar group 49 pt above the home-indicator area with
/// the capsule overflowing 13 pt into it. Ours is 6 pt shorter at the user's request, same overhang.
struct VoryTabBar: View {
    @Environment(AppModel.self) private var model
    var tabs: [AppModel.AppTab]
    /// Horizontal along the bottom (every phone, the open Duo held upright), or a vertical
    /// strip on a side edge where the system lays its own bars that way (the closed iPhone
    /// Duo, the open Duo in landscape): the same capsule and circles, stacked.
    var axis: Axis = .horizontal
    var compose: () -> Void
    /// The full New Message sheet (bots, project, files).
    var composeFull: () -> Void = {}
    /// A fresh chat straight into voice mode, with the bot named (nil: the current one).
    var voice: (String?) -> Void = { _ in }
    /// What a tap and a press and hold do (Settings › Appearance › New Chat button).
    @AppStorage(ComposeAction.tapKey) private var tapRaw = ComposeAction.tapDefault.rawValue
    @AppStorage(ComposeAction.holdKey) private var holdRaw = ComposeAction.holdDefault.rawValue
    /// Settings › Appearance › Voice button: the mic circle beside the bar, or not (the capsule
    /// takes the room). Applies as it is switched, no relaunch.
    @AppStorage(Self.showVoiceKey) private var showVoice = true
    static let showVoiceKey = "tabBar.showVoice"
    /// Settings › Appearance › Tab labels: the word under the selected tab's icon, or icons only.
    @AppStorage(Self.showLabelsKey) private var showLabels = true
    static let showLabelsKey = "tabBar.showLabels"

    private func run(_ action: ComposeAction) {
        switch action {
        case .quick: compose()
        case .sheet: composeFull()
        case .none: break
        }
    }

    /// Where the finger is along the capsule while it drags the lens; nil when not dragging.
    @State private var dragX: CGFloat?
    @State private var pressStart: Date?
    /// The tab the lens is over while it is dragged: tinted, not yet shown. The page switches
    /// when the lens is dropped (Matt, 2026-10-11: switching as it passed made the drag lag,
    /// each pass cross-faded two whole pages under a live glass lens).
    @State private var hoverTab: AppModel.AppTab?

    /// The system capsule is 62 pt; the user wanted it a little shorter, bottom edge kept.
    private let barHeight: CGFloat = 56
    private let inset: CGFloat = 4
    private let sideMargin: CGFloat = 21
    /// Between the capsule and the circles, and between the circles: half what it was (the
    /// bar had a gap on each side of the mic that read as empty space).
    private let circleGap: CGFloat = 6
    /// The window's bottom safe-area inset, read from the window as it is now (`WindowGeometry`):
    /// 34 pt on phones with a home indicator, 0 on a home-button phone (iPhone SE), which iOS 26
    /// still runs on, and whatever the window has after a fold or a resize.
    @Environment(\.windowGeometry) private var windowGeometry
    /// How far the capsule hangs into the home-indicator area: the full 13 pt when there is one.
    /// Without one the capsule would hang off the screen, so it hangs by what is there (nothing on
    /// an SE) and keeps the rest as a gap above the screen edge instead.
    nonisolated static func overhang(safeBottom: CGFloat) -> CGFloat { min(13, safeBottom) }
    /// What the bar reserves above the home-indicator area (the system bar group's 49 pt); the
    /// capsule is drawn overflowing below it.
    nonisolated static func reservedHeight(safeBottom: CGFloat) -> CGFloat { 56 - overhang(safeBottom: safeBottom) + max(0, 13 - safeBottom) }
    /// The same, for this window as it is now.
    static func reservedHeight(in geometry: WindowGeometry) -> CGFloat { reservedHeight(safeBottom: geometry.safeArea.bottom) }
    /// What a vertical strip takes from the window's width when the bar stands beside it (a strip
    /// too narrow to hold it): the capsule plus a margin each side.
    static let reservedWidth: CGFloat = 56 + 2 * 10
    /// The system's strip items, measured on the closed iPhone Duo: 50 pt wide, their centre
    /// line 48 pt in from the window's edge, 10 pt between groups; the status items at the top
    /// of the strip end about 150 pt down. Ours line up with them (Matt).
    static let stripItemWidth: CGFloat = 50
    static let stripCentreFromEdge: CGFloat = 48
    static let stripGroupGap: CGFloat = 10
    static let stripStatusAllowance: CGFloat = 156
    /// Down a strip the bar is compact, like the system's vertical bars: icons only, in 46 pt
    /// slots and circles, so it fits under the navigation items the strip already holds.
    private let verticalSlot: CGFloat = 42
    private var circleSize: CGFloat { axis == .vertical ? 42 : barHeight }

    var body: some View {
        let gap = axis == .horizontal ? circleGap : Self.stripGroupGap
        GlassEffectContainer(spacing: gap) {
            // The capsule then the circles, side by side along the bottom or stacked down a strip.
            let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: gap)) : AnyLayout(VStackLayout(spacing: gap))
            layout {
                capsule
                // Voice: one tap is a fresh chat with the current bot, straight into voice mode;
                // held, it offers the bots (#237). With four tabs at most the capsule keeps 49 pt
                // slots on the narrowest phone. Off in Settings › Appearance, it is not there and
                // the capsule is wider (voice mode still starts from a chat and the + panel).
                if showVoice {
                    Menu {
                        ForEach(model.runtime?.profiles ?? []) { p in
                            Button { voice(p.name) } label: { Label(p.label, systemImage: "person.fill") }
                        }
                    } label: {
                        Image(systemName: "mic.fill").font(.system(size: axis == .vertical ? 19 : 22, weight: .medium))
                            .frame(width: circleSize, height: circleSize)
                            .glassEffect(.regular.interactive(), in: .circle)
                    } primaryAction: {
                        voice(nil)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .disabled(model.runtime == nil)
                    .accessibilityLabel("Voice chat")
                    .accessibilityHint("Tap for a voice chat with the current bot; press and hold to choose a bot")
                    .accessibilityIdentifier("chats.voice")
                    .transition(.scale.combined(with: .opacity))
                }
                Button { run(ComposeAction.tap(tapRaw)) } label: {
                    // Centred on the square, not the glyph: the pencil hangs off its top-right
                    // corner. Measured from a simulator screenshot (the square sat 2.5 pt low).
                    Image(systemName: "square.and.pencil").font(.system(size: axis == .vertical ? 20 : 23, weight: .medium))
                        .offset(x: 0, y: -2.5)
                        .frame(width: circleSize, height: circleSize)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    let action = ComposeAction.hold(holdRaw)
                    guard action != .none else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    run(action)
                })
                .disabled(model.runtime == nil)
                .accessibilityLabel("New Chat")
                .accessibilityHint("Tap to \(ComposeAction.tap(tapRaw).spoken); press and hold to \(ComposeAction.hold(holdRaw).spoken)")
                .accessibilityIdentifier("chats.new")
            }
        }
        .padding(axis == .horizontal ? .horizontal : .vertical, axis == .horizontal ? sideMargin : 0)
        // Along the bottom: reserve only the part above the home-indicator area, like the
        // system bar group; the capsule itself is drawn overflowing into it. Down a strip: the
        // strip's width, the stack kept to its top like the system's.
        .frame(width: axis == .vertical ? Self.stripItemWidth : nil, height: axis == .horizontal ? Self.reservedHeight(in: windowGeometry) : nil,
               alignment: axis == .horizontal ? .top : .top)
        .animation(.snappy(duration: 0.25), value: showVoice)
    }

    private var capsule: some View {
        GeometryReader { geo in
            // The slots run along the capsule's length (x along the bottom, y down a strip).
            let length = axis == .horizontal ? geo.size.width : geo.size.height
            let thickness = axis == .horizontal ? geo.size.height : geo.size.width
            let slotAlong = max(1, (length - inset * 2) / CGFloat(max(1, tabs.count)))
            let slotAcross = thickness - inset * 2
            let slotWidth = axis == .horizontal ? slotAlong : slotAcross
            let slotHeight = axis == .horizontal ? slotAcross : slotAlong
            let selectedIndex = CGFloat(tabs.firstIndex(of: model.selectedTab) ?? 0)
            let dragging = dragX != nil
            let lensAlong: CGFloat = {
                guard let x = dragX else { return inset + selectedIndex * slotAlong }
                return min(max(inset, x - slotAlong / 2), length - inset - slotAlong)
            }()
            let lensX = axis == .horizontal ? lensAlong : inset
            let lensY = axis == .horizontal ? inset : lensAlong
            ZStack(alignment: .topLeading) {
                // The lens: clear glass under the selected slot, or wherever the finger holds it
                // (grown a little while lifted). Under the icons at rest so the selected one stays
                // crisp; over them while dragged so it refracts them as it passes, like the system's.
                GlassEffectContainer {
                    Capsule().fill(.clear)
                        .frame(width: slotWidth, height: slotHeight)
                        .glassEffect(.clear.interactive(), in: .capsule)
                }
                .scaleEffect(dragging ? 1.12 : 1)
                .offset(x: lensX, y: lensY)
                .animation(dragging ? .interactiveSpring(response: 0.18) : .snappy(duration: 0.32), value: lensAlong)
                .animation(.snappy(duration: 0.22), value: dragging)
                .allowsHitTesting(false)
                .zIndex(dragging ? 2 : 0)
                iconRow(slotWidth: slotWidth, slotHeight: slotHeight, dragging: dragging)
                    .zIndex(1)
                // While dragged, a second copy of the icons rides on top of the lens, masked to
                // the lens minus its rim, so the icon under it stays crisp and only the edge
                // refracts (the system bar draws its icons twice for the same reason).
                if dragging {
                    let lensW = slotWidth * 1.12, lensH = slotHeight * 1.12
                    iconRow(slotWidth: slotWidth, slotHeight: slotHeight, dragging: true)
                        .mask {
                            Capsule()
                                .frame(width: lensW - 8, height: lensH - 8)
                                .position(x: lensX + slotWidth / 2, y: lensY + slotHeight / 2)
                        }
                        .animation(.interactiveSpring(response: 0.18), value: lensAlong)
                        .allowsHitTesting(false)
                        .zIndex(3)
                }
            }
            .contentShape(Capsule())
            .gesture(barGesture(slotAlong: slotAlong))
        }
        .frame(width: axis == .vertical ? verticalSlot + inset * 2 : nil,
               height: axis == .horizontal ? barHeight : CGFloat(max(1, tabs.count)) * verticalSlot + inset * 2)
        .glassEffect(.regular, in: .capsule)
    }

    private func iconRow(slotWidth: CGFloat, slotHeight: CGFloat, dragging: Bool) -> some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            ForEach(tabs, id: \.self) { tab in
                slot(tab, dragging: dragging).frame(width: slotWidth, height: slotHeight)
            }
        }
        .padding(inset)
    }

    /// One tab: a large icon on its own, or a smaller icon over its label when it is selected
    /// (no labels at all while the lens is being dragged, like the system bar, or when
    /// Settings › Appearance › Tab labels is off).
    @ViewBuilder private func slot(_ tab: AppModel.AppTab, dragging: Bool) -> some View {
        let selected = (hoverTab ?? model.selectedTab) == tab
        let labelled = selected && !dragging && showLabels && axis == .horizontal
        VStack(spacing: 2) {
            icon(for: tab, size: axis == .vertical ? 21 : (labelled ? 21 : 25))
                .frame(height: axis == .vertical ? 26 : (labelled ? 24 : 30))
            if labelled {
                Text(tab.title).font(.system(size: 10, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(selected ? Color.vory : Color.primary)
        .animation(.snappy(duration: 0.24), value: labelled)
        .overlay(alignment: .top) {
            if let b = badge(for: tab) { b.offset(x: 14, y: 4) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { select(tab) }
    }

    /// A press moves the lens under the finger once it is held for a moment or slides sideways;
    /// the tab under the lens is tinted as it passes and the page switches to it when the lens
    /// is dropped. A quick press is a tap on that tab.
    private func barGesture(slotAlong: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if pressStart == nil { pressStart = Date() }
                let held = Date().timeIntervalSince(pressStart ?? Date()) > 0.22
                let slid = abs(axis == .horizontal ? v.translation.width : v.translation.height) > 8
                guard dragX != nil || held || slid else { return }
                if dragX == nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                let along = axis == .horizontal ? v.location.x : v.location.y
                dragX = along
                if let tab = tab(at: along, slotAlong: slotAlong), tab != (hoverTab ?? model.selectedTab) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    hoverTab = tab
                }
            }
            .onEnded { v in
                let along = axis == .horizontal ? v.location.x : v.location.y
                let dropped = dragX != nil
                dragX = nil
                pressStart = nil
                hoverTab = nil
                guard let tab = tab(at: along, slotAlong: slotAlong) else { return }
                if dropped {
                    if tab != model.selectedTab { withAnimation(.snappy(duration: 0.28)) { model.selectedTab = tab } }
                } else {
                    select(tab)
                }
            }
    }

    private func tab(at along: CGFloat, slotAlong: CGFloat) -> AppModel.AppTab? {
        let i = Int((along - inset) / slotAlong)
        return tabs.indices.contains(i) ? tabs[i] : (along < inset ? tabs.first : tabs.last)
    }

    /// A tap on the selected tab while it is deeper than its root page goes back to that page,
    /// like the system bar.
    private func select(_ tab: AppModel.AppTab) {
        // A tab chosen by hand is where the person wants to be: no going back after a chat.
        model.composeReturnTab = nil
        if tab == model.selectedTab {
            if model.tabAtRoot[tab] == false { model.popToRoot[tab, default: 0] += 1 }
            model.tabReselected[tab, default: 0] += 1
            return
        }
        withAnimation(.snappy(duration: 0.28)) { model.selectedTab = tab }
    }

    @ViewBuilder private func icon(for tab: AppModel.AppTab, size: CGFloat) -> some View {
        if tab == .bots {
            VoryOutlineIcon().frame(width: size * 1.5, height: size * 1.28)
        } else {
            Image(systemName: tab.symbol).font(.system(size: size, weight: .medium))
        }
    }

    /// Chats counts waiting cards; Settings flags a gateway that needs a restart, or a companion
    /// update waiting under Software Update.
    private func badge(for tab: AppModel.AppTab) -> CountBadge? {
        switch tab {
        case .chats:
            let n = model.runtime?.needsAttention.count ?? 0
            return n > 0 ? CountBadge(n) : nil
        case .settings:
            if model.runtime?.restartRequired != nil { return CountBadge(1) }
            return model.companionUpdateAvailable ? CountBadge(1) : nil
        default:
            return nil
        }
    }
}

/// Hides the custom tab bar while this view is on screen. On the Chats tab the list's own
/// navigation path hides the bar the instant a push begins and shows it the instant a pop
/// begins, so this only counts on the other tabs.
struct HidesTabBar: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var countedOn: AppModel.AppTab?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard countedOn == nil, model.selectedTab != .chats else { return }
                countedOn = model.selectedTab
                model.tabBarHiders[model.selectedTab, default: 0] += 1
            }
            .onDisappear {
                guard let tab = countedOn else { return }
                countedOn = nil
                model.tabBarHiders[tab] = max(0, (model.tabBarHiders[tab] ?? 0) - 1)
            }
    }
}

/// Marks a tab's root page: on screen means the tab is at its root. Chats reports through its
/// navigation path instead (a pushed chat keeps the list alive underneath). A tap on the tab
/// while deeper pops the stack the way a swipe back would, animated.
struct TabRoot: ViewModifier {
    @Environment(AppModel.self) private var model
    /// The page's pull-to-refresh state when its `.reloadable` is applied outside this marker
    /// (Bots, Files): by environment then, by preference when it sits inside (Home, Projects,
    /// the Board, Status, Sessions, Tasks). The bar's title capsule hosts the wheel either way;
    /// Bots and Files had no wheel (Matt, 2026-10-12).
    @Environment(PullRefreshState.self) private var pullAround: PullRefreshState?
    @State private var pullBelow: PullRefreshState?
    var tab: AppModel.AppTab
    private func publishPull() { model.pullStates[tab] = pullBelow ?? pullAround }
    func body(content: Content) -> some View {
        content
            // Every root page shares the Chats page's heading (Matt, 2026-10-12); the pull-to-
            // refresh wheel sits beside it on the pages that can refresh.
            .pageHeading(tab.title, on: !model.wideLayout && !MorphTopBar.on)
            // Out of the accessibility tree while another tab is up. RootView hides the whole
            // page, but that flag sits outside the navigation stack, a UIKit container the flag
            // does not pass through: Home's blocks, bots and chat rows stayed in the Chats
            // tab's tree, off-screen, and VoiceOver and XCTest found the same chat twice (#326).
            .accessibilityHidden(model.selectedTab != tab)
            // The page's pull-to-refresh state, for the bar's title capsule to host its wheel.
            .onPreferenceChange(PullRefreshKey.self) { r in Task { @MainActor in pullBelow = r.state; publishPull() } }
            .onChange(of: pullAround.map(ObjectIdentifier.init), initial: true) { _, _ in publishPull() }
            // Under the morph prototype the bar draws the title: the stack's own (large by
            // default on a root) goes, as it does on Chats, so no root shows two.
            .navigationBarTitleDisplayMode(MorphTopBar.active(model) ? .inline : .automatic)
            .toolbar(removing: MorphTopBar.active(model) ? .title : nil)
            // An empty bar collapses (on the Duo the search drawer rode up under the capsules):
            // an invisible item keeps the bar at its height under the prototype.
            .toolbar { if MorphTopBar.active(model) { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 44).accessibilityHidden(true) } } }
            // "At root" is set by the probe below: on a swipe back SwiftUI's onAppear fires as
            // the pop begins, and the bar's capsules came back over the pushed page before it
            // had moved (Matt, 2026-10-12: "swiping back on other pages is broken"). The probe
            // waits for an interactive pop to finish (and stays put if it is cancelled).
            .onDisappear { model.tabAtRoot[tab] = false }
            .background(PopToRootProbe(tab: tab))
            .background(RootArrivalProbe { model.tabAtRoot[tab] = true })
    }
}

/// Tells the root page it has arrived: at once on a plain appearance or a Back button's pop,
/// at the end of an interactive pop (not at all if the swipe is cancelled).
struct RootArrivalProbe: UIViewRepresentable {
    /// The last decision, for the geometry probe's banner (a UI test's stills).
    nonisolated(unsafe) static var last = "none"
    let arrived: () -> Void
    func makeUIView(context: Context) -> ArrivalView { let v = ArrivalView(); v.isUserInteractionEnabled = false; v.arrived = arrived; return v }
    func updateUIView(_ v: ArrivalView, context: Context) { v.arrived = arrived }
    final class ArrivalView: UIView {
        var arrived: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            let nav = parentViewController?.navigationController
            if let c = nav?.transitionCoordinator, c.isInteractive {
                Perf.stamp("root probe: interactive pop, waiting"); RootArrivalProbe.last = "interactive, waiting"
                c.notifyWhenInteractionChanges { [weak self] ctx in
                    Perf.stamp("root probe: interaction ended cancelled=\(ctx.isCancelled)"); RootArrivalProbe.last = "interaction ended cancelled=\(ctx.isCancelled)"
                    if !ctx.isCancelled { self?.arrived?() }
                }
            } else {
                let why = nav == nil ? "no nav" : (nav?.transitionCoordinator == nil ? "coordinator nil" : "not interactive")
                Perf.stamp("root probe: arrived at once (\(why))"); RootArrivalProbe.last = "at once (\(why))"
                arrived?()
            }
        }
    }
}

/// A zero-size view under a tab's root page that finds the UIKit navigation controller behind
/// the NavigationStack and pops it to the root, animated, whenever `popToRoot` bumps.
private struct PopToRootProbe: UIViewRepresentable {
    @Environment(AppModel.self) private var model
    var tab: AppModel.AppTab

    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ v: UIView, context: Context) {
        let bump = model.popToRoot[tab, default: 0]
        guard bump != context.coordinator.seen else { return }
        context.coordinator.seen = bump
        guard bump > 0 else { return }
        DispatchQueue.main.async {
            var r: UIResponder? = v
            while let n = r { if let nav = n as? UINavigationController { nav.popToRootViewController(animated: true); return }; r = n.next }
            // The probe sits in the root page, which is inside the stack's hosting controller.
            if let nav = v.parentViewController?.navigationController { nav.popToRootViewController(animated: true) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var seen = 0 }
}

private extension UIView {
    var parentViewController: UIViewController? {
        var r: UIResponder? = self
        while let n = r { if let vc = n as? UIViewController { return vc }; r = n.next }
        return nil
    }
}

extension View {
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }
    func tabRoot(_ tab: AppModel.AppTab) -> some View { modifier(TabRoot(tab: tab)) }
}
