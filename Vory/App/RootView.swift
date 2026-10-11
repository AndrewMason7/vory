import os
import SwiftUI
import VoryCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Two columns and the wide chat layout: see `wideLayout` below.
    private var wide: Bool { Self.isWide(regular: sizeClass == .regular, size: windowGeometry.bounds.size) }
    nonisolated static func isWide(regular: Bool, size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return regular }   // not measured yet
        return regular && (size.width > size.height || size.width >= 700)
    }
    /// The window's geometry for this scene, read from the window on every layout (see
    /// `WindowGeometry`); every view that lays out against the window reads it from the environment.
    @State private var windowGeometry = WindowGeometry()
    /// DEBUG: `-vory-show-tour` shows the first-run tour over a configured app.
    static let forceTour: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-vory-show-tour")
        #else
        return false
        #endif
    }()
    /// DEBUG: `-vory-show-welcome` shows the first screen (Get Started / Restore from iCloud)
    /// over a configured app.
    static let forceWelcome: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-vory-show-welcome")
        #else
        return false
        #endif
    }()
    /// Shown once, right after the first gateway is saved: install the Companion now or later.
    @AppStorage("companionPromptShown") private var companionPromptShown = false
    @AppStorage("launchTab") private var launchTab = "chats"
    @AppStorage(TabLayout.storageKey) private var rootLayoutRaw = ""
    @AppStorage("notificationsSetupCardDone") private var setupCardDone = false
    @State private var showCompanionPrompt = false
    /// The first gateway was just saved: the Companion prompt is owed once the gateway is
    /// signed in and nothing else is asking.
    @State private var companionDue = false
    @State private var showInstaller = false
    /// The Companion's version when the gateway already runs one: the prompt then only asks to allow notifications.
    @State private var companionFound: String?
    /// The chosen first screen while its page is still hidden: the Board is off the bar until
    /// the plugin's probe answers, so "Open Vory on: Board" opened on Chats. It waits for the
    /// answer, a few seconds at most, as the Mac's launch page does.
    @State private var launchTabPending: AppModel.AppTab?

    var body: some View {
        ZStack {
            if !model.hasConnections || Self.forceTour || Self.forceWelcome {
                OnboardingView(skipWelcome: Self.forceTour)
            } else {
                MainTabView()
            }
            if model.lock.isLocked {
                LockScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.lock.isLocked)
        .background { WindowGeometryReader(geometry: windowGeometry).ignoresSafeArea() }
        // The fold and the camera, for every floating piece below (Step D).
        .modifier(ReservedRegionsEnvironment())
        #if DEBUG
        // `-vory-geometry-probe`: the window's numbers in the corner, for reading a pose off a
        // screenshot (the Duo simulator has no other way to report its insets).
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.arguments.contains("-vory-geometry-probe") {
                VerticalBarEdge { edge in
                    let g = windowGeometry
                    Text(String(format: "%.0fx%.0f  safe t%.0f l%.0f b%.0f r%.0f  bar %@  wide %@  hidden %@ kb %@ open %@ hiders %d mw %@ v %@", g.bounds.width, g.bounds.height, g.safeArea.top, g.safeArea.leading, g.safeArea.bottom, g.safeArea.trailing, edge.map { $0 == .leading ? "leading" : "trailing" } ?? "bottom", wide ? "yes" : "no", model.tabBarHidden ? "yes" : "no", model.keyboardUp ? "yes" : "no", model.chatsPathOpen ? "yes" : "no", model.tabBarHiders[model.selectedTab] ?? 0, model.wideLayout ? "yes" : "no", model.tabBarVertical ? "yes" : "no"))
                        .font(.caption2.monospaced()).padding(4).background(.yellow.opacity(0.9)).foregroundStyle(.black)
                        .padding(.top, 40).allowsHitTesting(false)
                }
            }
        }
        #endif
        .environment(\.windowGeometry, windowGeometry)
        // Wide on a regular-width window that is wider than tall or at least 700 pt wide (any
        // iPad, the open Duo in landscape); the phone layout otherwise, which includes the open
        // Duo upright (669 pt: Matt chose one column there, 2026-10-10) and a narrow Stage
        // Manager or Split View window. The window's shape decides, never the device or a pose.
        .environment(\.wideLayout, wide)
        .onChange(of: wide, initial: true) { _, w in model.wideLayout = w }
        // Belt and braces: the same value again once the layout has settled after a change of
        // shape (the Duo's turn from one column to two).
        .task(id: wide) { model.wideLayout = wide }
        // The probe answered and the chosen page is on the bar now: open on it, unless the
        // person has already gone somewhere else.
        .onChange(of: model.hiddenTabs) { was, hidden in
            guard let tab = launchTabPending, was.contains(tab), !hidden.contains(tab) else { return }
            launchTabPending = nil
            if model.selectedTab == TabLayout.parse(rootLayoutRaw).visible(hiding: hidden).first || model.selectedTab == .chats { model.selectedTab = tab }
        }
        // The bar steps aside for the keyboard (a name field in Settings had it floating on top).
        // A keyboard is up when its frame overlaps the window now (`WindowGeometry`), not when a
        // will-show was seen: a turn of the open Duo took the keyboard away without a will-hide
        // and the bar stayed hidden behind it; the iPad's hardware-keyboard bar counts the same way.
        .onChange(of: windowGeometry.keyboardOverlap > 0, initial: true) { _, up in model.keyboardUp = up }
        .onAppear {
            // Once per phone: the bar becomes Home, Chats, Bots, Settings. It can be changed after.
            if !UserDefaults.standard.bool(forKey: TabLayout.homeFirstAppliedKey) {
                rootLayoutRaw = TabLayout.default.encoded
                UserDefaults.standard.set(true, forKey: TabLayout.homeFirstAppliedKey)
            }
            // The chosen first screen (Settings › Home), when it is still on the bar.
            // A page the gateway cannot show (the Board without its plugin) is not opened on: it drew blank.
            if let tab = AppModel.AppTab(rawValue: launchTab), TabLayout.parse(rootLayoutRaw).visible().contains(tab) {
                if !model.hiddenTabs.contains(tab) {
                    model.selectedTab = tab
                } else {
                    launchTabPending = tab
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(8))
                        launchTabPending = nil
                    }
                }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-vory-show-companion-prompt") { showCompanionPrompt = true }
            if ProcessInfo.processInfo.arguments.contains("-vory-show-setup") { showInstaller = true }
            if AppModel.forceSignIn, let c = model.store.active { model.signInPrompt = [c] }
            // The intents' work without Siri: `-vory-start-voice` does what "Start voice mode" does;
            // `-vory-ask <question>` runs "Ask Vory" and logs the answer (subsystem dev.vory).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-vory-start-voice") { model.requestVoiceMode() }
            if let i = args.firstIndex(of: "-vory-ask"), i + 1 < args.count {
                let question = args[i + 1]
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    let answer = await SiriAsk.ask(question)
                    UtteranceListener.log.notice("Ask Vory → \(answer, privacy: .public)")
                }
            }
            #endif
        }
        .onChange(of: model.hasConnections) { had, has in
            if !had, has, !companionPromptShown { companionDue = true; offerCompanion() }
        }
        // One sheet at a time, and none over the lock: the sign-in a restore owes comes first,
        // the Companion prompt once that is settled (its check needs a signed-in gateway).
        .onChange(of: model.signInPrompt.isEmpty) { _, _ in offerCompanion() }
        .onChange(of: model.needsSignIn == nil) { _, _ in offerCompanion() }
        .onChange(of: model.lock.isLocked) { _, _ in offerCompanion() }
        .sheet(isPresented: Binding(get: { !model.signInPrompt.isEmpty && !model.lock.isLocked && !showCompanionPrompt && !showInstaller },
                                    set: { if !$0 { model.signInPrompt = [] } })) {
            GatewaySignInSheet(connections: model.signInPrompt).withAppModel()
        }
        .sheet(isPresented: $showCompanionPrompt) {
            CompanionPromptSheet(found: companionFound, install: {
                // Installed from here: the Settings suggestion never needs to show.
                setupCardDone = true
                showCompanionPrompt = false
                showInstaller = true
            }, allow: {
                // Allowed: the token arrives, the device file goes up, the Companion sends here.
                setupCardDone = true
                showCompanionPrompt = false
                Task { _ = await model.push.requestAuthorization() }
            }, later: {
                setupCardDone = false
                showCompanionPrompt = false
            })
            .withAppModel()
        }
        .sheet(isPresented: $showInstaller) {
            NavigationStack {
                SetupWizardHost()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInstaller = false } } }
            }
            .withAppModel()
        }
    }
}

extension RootView {
    /// Shows the Companion prompt when it is owed and nothing stands in its way.
    private func offerCompanion() {
        guard companionDue, !companionPromptShown, model.hasConnections, model.signInPrompt.isEmpty, model.needsSignIn == nil, !model.lock.isLocked else { return }
        companionDue = false
        companionPromptShown = true
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            // A gateway set up from another device already has the Companion: no install to offer.
            if let rt = model.runtime { companionFound = await CompanionPromptSheet.installedVersion(on: rt) }
            showCompanionPrompt = true
        }
    }
}

struct LockScreenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Vory is locked").font(.title2.weight(.semibold))
                if let e = model.lock.lastError { Text(e).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                Button("Unlock with \(model.lock.biometryName)") { Task { await model.lock.unlock() } }
                    .buttonStyle(.glassProminent)
            }
            .padding()
        }
        .task { await model.lock.unlock() }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowGeometry) private var windowGeometry
    @AppStorage(TabLayout.storageKey) private var layoutRaw = ""

    var body: some View {
        let tabs = TabLayout.parse(layoutRaw).visible(hiding: model.hiddenTabs)
        let barHeight = VoryTabBar.reservedHeight(in: windowGeometry)
        // Where the system would put a vertical bar (the closed Duo's strip, the open Duo in
        // landscape), Vory's own bar goes there too, stacked on that edge (decision 1): the
        // pages are inset by its width instead of its height. Nil: along the bottom, as ever.
        VerticalBarEdge { edge in
            let vertical = edge != nil
            let pages = ZStack {
                // Every page stays alive (its navigation stack, scroll position, drafts); only the
                // selected one is visible and touchable, which is what the system TabView does too.
                ForEach(tabs, id: \.self) { tab in
                    content(for: tab)
                        .opacity(model.selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(model.selectedTab == tab)
                        .accessibilityHidden(model.selectedTab != tab)
                }
            }
            // Reserves the bar's height (or width) so lists end before it; the bar itself is
            // hidden (slid off its edge) inside a chat and the setup wizard, and the pages then
            // use the full height. The bar is never removed from the tree: an insert/remove
            // transition got stuck on the first chat opened after launch (the bar stayed,
            // tappable, over the composer). It slides and fades instead, and its reserved
            // size collapses to nothing.
            let bar = VoryTabBar(tabs: tabs, axis: vertical ? .vertical : .horizontal, compose: { compose() }, composeFull: { composeFull() }, voice: { voiceChat($0) })
                .offset(x: model.tabBarHidden && vertical ? (edge == .leading ? -140 : 140) : 0,
                        y: model.tabBarHidden && !vertical ? 140 : 0)
                .opacity(model.tabBarHidden ? 0 : 1)
                // The slide and fade animate; the reserved size below does not. Animating the
                // safe-area inset while a chat opened made its thread bounce up and down.
                .animation(.snappy(duration: 0.3), value: model.tabBarHidden)
                .frame(width: vertical ? (model.tabBarHidden ? 0 : VoryTabBar.reservedWidth) : nil,
                       height: vertical ? nil : (model.tabBarHidden ? 0 : barHeight),
                       alignment: .top)
                // Not tappable while it slides away: a tap then switched tabs under an open chat.
                .allowsHitTesting(!model.tabBarHidden)
                .accessibilityHidden(model.tabBarHidden)
            Group {
                if let edge {
                    // Into the system's strip itself (the window's inset on that side, where the
                    // status bar and the navigation bars' items already stand), at the strip's
                    // foot under those items, so the pages keep the width the strip leaves them.
                    // A strip too narrow for the capsule gets the bar beside it instead.
                    let strip = edge == .leading ? windowGeometry.safeArea.leading : windowGeometry.safeArea.trailing
                    if strip >= VoryTabBar.stripItemWidth {
                        // One column with the system's items: their width, their centre line
                        // (measured on the closed Duo: 50 pt wide, centred 48 pt from the edge).
                        // On the closed display the stack sits at the strip's foot, under the
                        // page's navigation items; on the open display (wide) it starts at the
                        // top, under the status items, as Apple orders vertical bars (Matt).
                        let outer = VoryTabBar.stripCentreFromEdge - VoryTabBar.stripItemWidth / 2
                        pages.overlay(alignment: wideAlignment(edge)) {
                            bar
                                .frame(width: VoryTabBar.stripItemWidth)
                                .padding(edge == .leading ? .leading : .trailing, outer)
                                .padding(.top, model.wideLayout ? VoryTabBar.stripStatusAllowance : 0)
                                // The overlay already ends above the home-indicator area; the stack
                                // keeps one group gap over it, no more. Padding it by the inset again
                                // pushed the stack up until its first tab touched the page's own
                                // strip items (the list's filter met Home, Matt).
                                .padding(.bottom, model.wideLayout ? 0 : VoryTabBar.stripGroupGap)
                                .ignoresSafeArea(.container, edges: edge == .leading ? .leading : .trailing)
                        }
                    } else {
                        pages.safeAreaInset(edge: edge, spacing: 0) { bar }
                    }
                } else {
                    pages.safeAreaInset(edge: .bottom, spacing: 0) { bar }
                }
            }
            .onChange(of: vertical, initial: true) { _, v in model.tabBarVertical = v }
        }
        // Lists on every page (roots and the pages pushed over them) do not pick up the bar's
        // inset on this iOS (their last rows ended under the bar), so their scroll content gets
        // the bar's height plus a breath of room. Inside a chat the bar is hidden and this is 0;
        // the thread measures its own margin against the composer.
        .contentMargins(.bottom, model.tabBarHidden || model.tabBarVertical ? 0 : barHeight + 16, for: .scrollContent)
        // No blank band under the bar at the top of any page: the first card sits right there.
        .contentMargins(.top, 0, for: .scrollContent)
        // "Read replies aloud" listens for finished replies in the chat in front.
        .task { VoiceCoordinator.shared.observeReplies() }
        .onChange(of: tabs) { _, now in
            // The selected tab was removed from the layout: fall back to Chats instead of a blank pane.
            if !now.contains(model.selectedTab) { model.selectedTab = .chats }
        }
    }

    /// The compose circle: a chat with the bot whose page is in front, otherwise a new chat on Chats.
    private func compose() {
        if model.selectedTab != .bots || model.composeProfile == nil { leaveForChats() }
        model.newChatRequest = UUID()
    }
    private func composeFull() {
        leaveForChats()
        model.newChatSheetRequest = UUID()
    }
    /// The mic circle: a fresh chat with the bot named under it, else the bot whose page is in
    /// front, else the selected one, straight into voice mode (#237).
    private func voiceChat(_ profile: String?) {
        let front = model.selectedTab == .bots ? model.composeProfile : nil
        leaveForChats()
        model.voiceChatRequest = AppModel.VoiceChatRequest(profile: profile ?? front)
    }
    /// Over to Chats for the new chat, remembering where the tap came from: a tester composed
    /// from Settings, closed the chat without sending, and found himself on Chats.
    private func leaveForChats() {
        model.composeReturnTab = model.selectedTab == .chats ? nil : model.selectedTab
        model.selectedTab = .chats
    }

    /// Where the vertical bar stands in the strip: the foot on a closed display, the top on an open one.
    private func wideAlignment(_ edge: HorizontalEdge) -> Alignment {
        switch (edge, model.wideLayout) {
        case (.leading, true): .topLeading
        case (.leading, false): .bottomLeading
        case (.trailing, true): .topTrailing
        case (.trailing, false): .bottomTrailing
        }
    }

    @ViewBuilder private func content(for tab: AppModel.AppTab) -> some View {
        switch tab {
        // The list beside the open chat on a wide window; the list with the chat pushed over it
        // on a narrow one. One view for both, so a fold or a resize keeps the open chat.
        case .chats: ChatsSplitPage()
        case .bots: BotsView()
        case .files: FilesView()
        case .settings: SettingsView()
        case .sessions: NavigationStack { SessionsView().navigationTitle("Sessions").tabRoot(.sessions) }
        case .cron: NavigationStack { CronView().navigationTitle("Scheduled Tasks").tabRoot(.cron) }
        case .kanban: NavigationStack { KanbanView().tabRoot(.kanban) }
        case .approvals: NavigationStack { ApprovalsView().navigationTitle("Approvals").tabRoot(.approvals) }
        case .system: NavigationStack { SystemView().navigationTitle("System").tabRoot(.system) }
        case .dashboard: NavigationStack { DashboardView().tabRoot(.dashboard) }
        case .projects: NavigationStack { ProjectsView().tabRoot(.projects) }
        case .status: NavigationStack { StatusView().tabRoot(.status) }
        }
    }
}


/// Publishes the window's reserved regions (the fold, the camera) into the environment.
private struct ReservedRegionsEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        ReservedRegionsReader { content }
    }
}
