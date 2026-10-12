import SwiftUI
import VoryCore

struct ConversationView: View {
    @Environment(AppModel.self) private var model
    var route: ChatRoute

    @State private var chat: ChatSession?
    @State private var loadError: String?
    @State private var showContext = false
    @State private var showProfile = false
    /// Rename chat, from the header's menu or a long press on the title pill (#286).
    @State private var renaming = false
    /// A bot whose "@name" was tapped in the thread: its card opens (#302).
    @State private var mentionedBot: String?
    @State private var composerText = ""
    /// A bubble chosen with Reply: quoted above the next message, like a reply in Messages.
    @State private var composerQuote = ""
    @State private var dockHeight: CGFloat = 60
    @State private var dockBottom: CGFloat = 0
    #if os(iOS)
    /// The tab bar's height under the chat, when it is there and runs along the bottom.
    private var barReserve: CGFloat { model.tabBarReserved && !model.tabBarVertical ? VoryTabBar.reservedHeight(in: windowGeometry) : 0 }
    /// The fold of a partly open Duo across the window (Step D): a dock the keyboard has pushed
    /// onto it moves up above it, with Apple's margin, so the field is never under the fold.
    @Environment(\.reservedRegions) private var regions
    private var foldLift: CGFloat {
        guard let fold = regions.horizontalFold, dockBottom > dockTop, dockTop > 0,
              fold.maxY + ReservedRegions.margin > dockTop, fold.minY < dockBottom else { return 0 }
        return dockBottom - fold.minY + ReservedRegions.margin
    }
    #endif
    /// The floating header's height on iOS; the Mac's header is the window toolbar, outside the thread.
    #if os(macOS)
    @State private var headerHeight: CGFloat = 0
    #else
    @State private var headerHeight: CGFloat = 96
    #endif
    @State private var dockTop: CGFloat = 0
    /// The header's bottom edge in window space (0 until measured): the thread's top margin ends
    /// there, whatever safe area or camera strip the header stands in, and it moves with them.
    @State private var headerBottom: CGFloat = 0
    /// The window as it is now, for the keyboard the dock moves up by (see `WindowGeometry`).
    @Environment(\.windowGeometry) private var windowGeometry
    @Environment(\.wideLayout) private var wide
    /// The keyboard's height above the home-indicator area. Tracked by hand for the dock as the
    /// transcript does for itself: SwiftUI's own avoidance hands the inset to any scroll view in
    /// the dock (the command list) instead of lifting the dock, which left the composer under
    /// the keyboard.
    @State private var sentInitial = false
    @State private var voiceStarted = false
    @State private var confirming: ApprovalConfirm?
    private var confirmTitle: String { confirming?.choice == "deny" ? "Deny this action?" : "Approve this action?" }
    /// Read where the bot's name shows, so a name saved on its card (#315) redraws the pill.
    @AppStorage(BotNames.storageKey) private var namesRaw = ""
    private func botLabel(_ chat: ChatSession) -> String { _ = namesRaw; return chat.runtime.profiles.first { $0.name == chat.profileName }?.label ?? chat.profileName }
    @Namespace private var glassNamespace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let chat {
                framed(chat)
                    .handsOff(chat)
                    .navigationTitle(chat.title)
                    .toolbar(.hidden, for: .navigationBar)
                    .sheet(isPresented: $showContext) { ContextBreakdownSheet(chat: chat).sheetFrame().withAppModel() }
                    // Approve/Deny from the Live Activity or a notification, with "Confirm
                    // approvals" on: asked once more here, on the card it concerns.
                    .alert(confirmTitle, isPresented: confirmShown) { confirmButtons(chat: chat) } message: { confirmMessage(chat: chat) }
                    .onChange(of: model.approvalConfirm, initial: true) { _, c in if let c, c.storedID == chat.storedID { confirming = c } }
                    .onAppear { model.visibleChatID = chat.storedID; model.visibleChat = chat; LocalNotifier.clearDelivered(for: chat.storedID) }
                    // What arrived for this chat while it was away is read now: its notifications
                    // leave Notification Center (a tester: "notifications won't stop even after
                    // attending to chat").
                    .onChange(of: chat.items.count) { _, _ in if model.visibleChatID == chat.storedID { LocalNotifier.clearDelivered(for: chat.storedID) } }
                    .onReceive(NotificationCenter.default.publisher(for: .hermesNewChatRequested)) { n in
                        guard model.visibleChatID == chat.storedID else { return }
                        model.composeProfile = (n.userInfo?["profile"] as? String) ?? chat.profileName
                        model.newChatRequest = UUID()
                    }
                    .onDisappear {
                        Perf.stamp("pop: conversation disappeared")
                        if model.visibleChatID == chat.storedID { model.visibleChatID = nil }
                        if model.visibleChat === chat { model.visibleChat = nil }
                        // Leaving a chat: back to the default bot, when one is chosen.
                        model.runtime?.returnToDefaultProfile()
                    }
                    .sheet(isPresented: $showProfile) { ProfileInfoSheet(chat: chat, profileName: chat.profileName).sheetFrame().withAppModel() }
                    .onChange(of: showProfile) { _, _ in Smooth.animate("botCard") }
                    .onChange(of: chat.isRunning, initial: true) { _, running in if running { Smooth.begin("turn") } else { Smooth.end("turn") } }
                    .sheet(isPresented: $renaming) { RenameChatSheet(chat: chat).sheetFrame(.compact).withAppModel() }
                    // A tapped "@bot" opens that bot's card; every other link goes its usual way.
                    .environment(\.openURL, OpenURLAction { url in
                        if let b = Mentions.bot(from: url) { mentionedBot = b; return .handled }
                        return .systemAction
                    })
                    .sheet(isPresented: Binding(get: { mentionedBot != nil }, set: { if !$0 { mentionedBot = nil } })) {
                        if let b = mentionedBot { ProfileInfoSheet(chat: nil, profileName: b).sheetFrame().withAppModel() }
                    }
                    .onChange(of: model.pendingRoute) { _, r in handle(route: r, chat: chat) }
                    // The morph prototype's Back, drawn outside the stack (MorphTopBar).
                    // The morph prototype's bar, drawn outside the stack, asks for the chat's actions
                    // here; only the chat the bar shows answers.
                    .onChange(of: model.chatRequest) { _, r in
                        guard let r, MorphState.shared.chat === chat else { return }
                        model.chatRequest = nil
                        switch r.kind {
                        case .back: dismiss()
                        case .profile: showProfile = true
                        case .rename: renaming = true
                        case .context: showContext = true
                        case .newChat: Task { await newChat() }
                        case .close: model.runtime?.closeChat(chat); dismiss()
                        }
                    }
                    .onAppear { handle(route: model.pendingRoute, chat: chat) }
                    // Whatever was typed survives leaving the chat: saved per session as it changes,
                    // restored when the chat opens, cleared by a send (the composer empties the text).
                    .onChange(of: composerText) { _, t in ComposerDrafts.save(t, for: chat) }
            } else if let loadError {
                ContentUnavailableView("Could not open chat", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ProgressView("Opening…")
            }
        }
        // Like Messages: inside a conversation the composer owns the bottom edge.
        .hidesTabBar()
        // The navigation bar is hidden, which switches off UIKit's edge-swipe back; put it back.
        .background(InteractivePopEnabler())
        .task { await open() }
    }

    /// The thread with its dock and header. On the phone both float over the thread (the text
    /// scrolls under their glass) and the keyboard is tracked by hand. On the Mac the dock is a
    /// bottom inset, so the scroll bar ends above it, and the window's title and subtitle are
    /// the header, with the menu as a chevron.
    private func framed(_ chat: ChatSession) -> some View {
        #if os(macOS)
        thread(chat)
            // With no toolbar strip the thread runs up under the bot's pill and the window's edge
            // at full strength, as on the phone (Matt, 2026-10-10: "remove the fades on the Mac
            // too"); the 68 pt top fade mask that used to soften it is gone.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dock(chat).frame(maxWidth: ChatStyle.readingColumn).frame(maxWidth: .infinity)
            }
            .navigationSubtitle(macSubtitle(chat))
            // No toolbar strip over the thread: the bot and the menu float on the window, as in
            // Messages. A short thread sits at the bottom with nothing above it, and the
            // toolbar's own background spread down over that gap as a lighter band.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                // The bot, in the middle over its thread; a click opens its profile.
                ToolbarItem(placement: .principal) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 7) {
                            // The pose the header shows on the phone, in the pill (the Mac's toolbar hosts it).
                            BotAvatar(profile: chat.profileName, size: 22, active: chat.isRunning, mood: BotFaceView.Mood(session: chat.storedID, state: chat.botState))
                            Text(botLabel(chat))
                                .font(.headline).lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                    }
                    .help(macSubtitle(chat))
                    .accessibilityIdentifier("chat.bot")
                }
                // The whole conversation by voice, in its own small window.
                ToolbarItem(placement: .primaryAction) {
                    let on = HandsFreeSession.shared.isActive(for: chat)
                    Button { if on { HandsFreeSession.shared.end() } else { HandsFreeSession.shared.start(chat: chat) } } label: {
                        Label(on ? "End Voice Mode" : "Voice Mode", systemImage: on ? "waveform.badge.mic" : "mic")
                    }
                    .tint(on ? .accentColor : nil)
                    .help(on ? "End Voice Mode (⇧⌘V)" : "Voice Mode (⇧⌘V)")
                    .accessibilityIdentifier("chat.voice")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ChatMenuItems(chat: chat, onProfile: { showProfile = true }, onRename: { renaming = true }, onContext: { showContext = true },
                                      onNewChat: { Task { await newChat() } }, onClose: { model.runtime?.closeChat(chat); dismiss() })
                    } label: { Label("Chat options", systemImage: "ellipsis") }
                    .menuIndicator(.hidden)
                    .help("Chat options")
                    .accessibilityIdentifier("chat.more")
                }
            }
        #else
        // The thread runs under the status bar (it ignores the top safe area) while the
        // header sits inside it, so the thread's top margin is the header plus that inset;
        // without it the first message starts under the pill.
        // Like Messages: header and dock float over the thread and the text scrolls under their glass.
        // No band under the header or under the dock (Matt, on the phone, 2026-10-10: "I
        // dont like the fade at the top or the bottom, you should see the messages from all
        // the way behind the message bar and behind the name"): the thread runs under both
        // and shows through their glass; only its rest margins keep the ends clear.
        ZStack(alignment: .bottom) {
            // The thread keeps the window's full height whatever the keyboard does; its bottom
            // margin is measured from the dock (`dockTop`), with the keyboard's final height
            // as the fallback (`keyboardOverlap`, the window's number, unanimated).
            thread(chat)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            // The dock is a sibling, not an overlay of the thread: it sits in the keyboard's own
            // safe area and rides the keyboard's animation (Matt, 2026-10-11: the bar "lags
            // behind the keyboard opening and closing", "the keyboard collapses completely
            // before the chat moves"): a hand-made spring took half a second against the
            // keyboard's quarter. On a wide layout it keeps to the reading column, as on the Mac.
            // Above the tab bar when the bar stands under the chat (a wide layout with the bar
            // along the bottom: the open Duo upright, the iPad): the pages do not pick up the
            // bar's inset on this iOS (see MainTabView), and the dock sat under the bar.
            dock(chat).frame(maxWidth: wide ? ChatStyle.readingColumn : .infinity).padding(.bottom, barReserve + foldLift)
        }
            // On a one-column layout the morph bar (MorphTopBar) draws the chat's controls; on a
            // wide window this header does, over the detail column.
            .overlay(alignment: .top) { if !MorphTopBar.active(model) { header(chat) } }
            // Voice mode runs out of sight under its pill, and in front on its own screen.
            .overlay(alignment: .top) {
                if HandsFreeSession.shared.isActive(for: chat), HandsFreeSession.shared.minimized {
                    HandsFreePill(chat: chat).padding(.top, headerHeight + 6).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: Binding(get: { HandsFreeSession.shared.isActive(for: chat) && !HandsFreeSession.shared.minimized },
                                                   set: { if !$0, HandsFreeSession.shared.isActive(for: chat) { HandsFreeSession.shared.minimized = true } })) {
                HandsFreeView(chat: chat).withAppModel()
            }
        #endif
    }

    private func open() async {
        guard let runtime = model.runtime else { loadError = "No gateway connected."; return }
        do {
            // A read-only look at another bot's chat carries its bot on its own calls and leaves
            // the selected bot alone; a chat of ours selects its bot first.
            if !route.readOnly, let p = route.profile, !p.isEmpty, runtime.selectedProfile != p { runtime.selectedProfile = p }
            // Stored chats return at once with the cached transcript and sync behind the header.
            // The chat keeps the bot it belongs to for as long as it is open, whatever is selected later.
            if let sid = route.storedID { chat = try await runtime.openChat(storedID: sid, title: route.title, profile: route.profile) }
            else { chat = try await runtime.newChat(cwd: route.cwd) }
            if let chat, composerText.isEmpty, let draft = ComposerDrafts.load(for: chat) { composerText = draft }
            #if DEBUG
            // For a UI test: `-vory-test-stage <name>.pdf` stages a small PDF of that name in
            // the chat as it opens, where the system file picker cannot be driven.
            if let chat, chat.staged.isEmpty, let name = UserDefaults.standard.string(forKey: "vory-test-stage"), !name.isEmpty {
                let pdf = "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"
                chat.stageAttachment(data: Data(pdf.utf8), name: name, kind: .pdf)
            }
            #endif
            // Opened for "Start voice mode" (the intent, or the Mac's ⇧⌘V with no chat open):
            // hands-free begins as soon as the chat exists.
            if let chat, model.voiceModeRequested {
                let wanted = model.voiceModeWanted
                model.voiceModeRequested = false
                if wanted { HandsFreeSession.shared.start(chat: chat) }
            }
            // The first message from the compose sheet goes out as soon as the chat exists.
            if let chat, !sentInitial, let t = route.initialText, !t.isEmpty || !route.initialAttachments.isEmpty {
                sentInitial = true
                for a in route.initialAttachments {
                    guard let u = a.localURL, let data = try? Data(contentsOf: u) else { continue }
                    chat.stageAttachment(data: data, name: a.name, kind: a.kind)
                    try? FileManager.default.removeItem(at: u)
                }
                _ = await chat.send(t)
                NotificationCenter.default.post(name: .hermesSessionsChanged, object: nil)
            }
            // Opened for voice mode (the Chats page's mic, the sheet's Voice mode): hands-free
            // begins once the first message, if any, is on its way, so the reply is spoken.
            if let chat, route.startVoice, !voiceStarted {
                voiceStarted = true
                // Not twice: a "Start voice mode" request may have started it a moment ago.
                if !HandsFreeSession.shared.isActive(for: chat) { HandsFreeSession.shared.start(chat: chat) }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    // The thread, the dock, the header and the keyboard watcher live apart from the body: inside
    // it they tipped the type checker over its limit.
    private func thread(_ chat: ChatSession) -> some View {
        #if os(macOS)
        // The dock is a bottom inset on the Mac: the thread needs no margins of its own.
        let (dockTopArg, fallback, top, fade): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        #else
        // Until the header has been measured, its default height plus the status bar's usual share.
        let (dockTopArg, fallback, top, fade) = (dockTop, dockHeight + windowGeometry.keyboardOverlap, headerHeight + windowGeometry.safeArea.top, ChatStyle.bandFade)
        #endif
        return TranscriptView(chat: chat, onEditMessage: editMessage, onOpenBot: { openBot($0, from: chat) }, onReply: reply,
                       dockTop: dockTopArg, fallbackInset: fallback, topInset: top, headerBottom: headerBottom, bandFade: fade)
            #if os(iOS)
            // The thread's margins (header above, dock and keyboard below) add up to a minimum
            // height. On a small phone with the keyboard up, or any phone with a tall card in
            // the dock, that is more than the space above the keyboard; the screen was then
            // measured as too tall and centred, which slid the header up under the status bar
            // by half the excess. The thread takes whatever it is offered instead.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            #endif
            .overlay {
                if let e = chat.resumeError, chat.items.isEmpty {
                    ContentUnavailableView("Could not open chat", systemImage: "exclamationmark.triangle", description: Text(e))
                        // Centred in what is left above the composer and the keyboard.
                        .padding(.bottom, dockHeight + windowGeometry.keyboardOverlap)
                }
            }
    }

    private func dock(_ chat: ChatSession) -> some View {
        BottomDock(chat: chat, text: $composerText, quote: $composerQuote, namespace: glassNamespace, readOnly: route.readOnly)
            .disabled(chat.resumeError != nil && chat.items.isEmpty)
            // A zero-height report (the dock not yet laid out) must not empty the thread's fallback margin.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0, $0 < 400 { dockHeight = $0 } }
            // The dock's bottom edge on screen (above the keyboard), where the band below it starts.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { dockBottom = $0 }
            // The dock's top edge on screen, keyboard included: the thread measures its
            // own bottom edge the same way and keeps its last line above this. It follows
            // every frame of an interactive keyboard dismiss too: the thread's rows no longer
            // rebuild for it (TranscriptRow takes its open states as values), so the thread
            // rides with the keyboard instead of holding and jumping (Matt, 2026-10-11).
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { dockTop = $0 }
            // The dock's frame for the UI tests (its own container: an identifier on a plain
            // view goes to every child, and the composer lost its name).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.dock")
    }
    private func header(_ chat: ChatSession) -> some View {
        // The fold of a partly open Duo, where it crosses the thread: the pill keeps off it.
        FoldReader { fold in
            // Back stays on a wide window too (Matt, 2026-10-10): it clears the column.
            ChatHeader(chat: chat, fold: fold, showBack: true,
                       onBack: { dismiss() }, onProfile: { showProfile = true }, onRename: { renaming = true }, onContext: { showContext = true },
                       onNewChat: { Task { await newChat() } }, onClose: { model.runtime?.closeChat(chat); dismiss() })
                // The header's own size and bottom edge (the reader around it is thread-sized):
                // its height, and its bottom in window space for the thread's top margin.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 < 200 { headerHeight = $0 } }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { headerBottom = $0 }
                // The header's frame for the UI tests (a container of its own, as the dock).
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("chat.header")
                .frame(maxHeight: .infinity, alignment: .top)
        }
            // One group for VoiceOver, placed after the thread and the dock in the accessibility
            // order. The accessibility hit test (XCUITest's isHittable, touch to explore) tries
            // the screen's elements from the last one back, as if the last were on top, and goes
            // into the first whose frame holds the point. The thread runs up under the header, so
            // with the header first (where its place on the screen put it) the thread was tried
            // first, and the last reply's group (each message is one) answered at Back's point.
            // Last, the header is tried first; drawn on top, it is also what a finger finds.
            // A swipe through the screen now reaches it after the composer: VoiceOver starts on
            // Back when the chat opens, and the pill is a heading for the rotor (`ChatHeader`).
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(-1)
    }
    // The confirmation alert's pieces live apart from the body: inside it they tipped the type
    // checker over its limit.
    private var confirmShown: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil; model.approvalConfirm = nil } })
    }
    @ViewBuilder private func confirmButtons(chat: ChatSession) -> some View {
        let deny = confirming?.choice == "deny"
        Button(deny ? "Deny" : "Approve once", role: deny ? .destructive : nil) {
            if let c = confirming, let card = chat.approvalCard(named: [c.cardID]) {
                Task { await chat.respond(card: card, result: ["choice": .string(c.choice)]) }
            }
            confirming = nil; model.approvalConfirm = nil
        }
        Button("Cancel", role: .cancel) { confirming = nil; model.approvalConfirm = nil }
    }
    @ViewBuilder private func confirmMessage(chat: ChatSession) -> some View {
        if let c = confirming, let card = chat.approvalCard(named: [c.cardID]), let a = card.approval {
            Text([a.description, a.command].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n"))
        } else {
            Text("The request is no longer waiting.")
        }
    }

    private func editMessage(_ text: String) { composerText = text }
    private func reply(_ text: String) { withAnimation(.snappy) { composerQuote = text } }
    /// A "Messaged X" notice: X's chat opens read-only, or the banner says why it cannot.
    private func openBot(_ handle: String, from chat: ChatSession) {
        Task { if let why = await model.openBotChat(handle) { chat.banner = why } }
    }

    private func newChat() async {
        guard let runtime = model.runtime else { return }
        do { chat = try await runtime.newChat() } catch { loadError = error.localizedDescription }
    }

    #if os(macOS)
    /// "unifi · grok-4.7 · Thinking…": the bot, its model, and the status while it works.
    private func macSubtitle(_ chat: ChatSession) -> String {
        let bot = chat.runtime.profiles.first { $0.name == chat.profileName }?.label ?? chat.profileName
        let model = chat.modelName.split(separator: "/").last.map(String.init) ?? chat.modelName
        var parts = [bot]
        if !model.isEmpty { parts.append(model) }
        // What it is working on, when the on-device model has written it; else the step it is on.
        if chat.isRunning { parts.append(ChatGoals.shared.goal(for: chat.storedID) ?? chat.statusLine ?? "Thinking…") } else if chat.isResuming { parts.append("Syncing…") }
        return parts.joined(separator: " · ")
    }
    #endif

    private func handle(route r: PendingRoute?, chat: ChatSession) {
        guard let r, r.storedSessionID == chat.storedID else { return }
        model.pendingRoute = nil
    }
}

/// Composer + queue + cards, in one glass container so the composer morphs into an approval card.
struct BottomDock: View {
    @Bindable var chat: ChatSession
    @Binding var text: String
    @Binding var quote: String
    var namespace: Namespace.ID
    /// Another bot's chat: a Read-only pill where the composer would be.
    var readOnly = false

    var body: some View {
        // The container is what lets the composer morph into a card; menus presented from
        // inside it (the + button) did not take taps on the phone, so the container only wraps
        // what morphs, and the composer draws its own glass.
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                if let banner = chat.banner {
                    HStack {
                        Text(banner).font(.footnote).lineLimit(3)
                        Spacer()
                        Button { chat.banner = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if !chat.queue.isEmpty { QueueStrip(chat: chat) }
                if readOnly {
                    // Another bot's chat, opened from a notice: look, don't type, and leave its
                    // cards to its owner.
                    Label("Read-only", systemImage: "lock")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("dock", in: namespace)
                        .accessibilityLabel("Read-only: this is another bot's chat")
                } else if let card = chat.firstCard {
                    if card.method == "approval" {
                        PendingCardView(chat: chat, card: card)
                            .glassEffectID("dock", in: namespace)
                            .contextMenu {
                                Button { Task { await chat.respond(card: card, result: ["choice": "once"]) } } label: { Label("Allow once", systemImage: "checkmark") }
                                Button { Task { await chat.respond(card: card, result: ["choice": "session"]) } } label: { Label("Allow for this session", systemImage: "checkmark.circle") }
                                Button { Task { await chat.respond(card: card, result: ["choice": "always"]) } } label: { Label("Always allow", systemImage: "checkmark.seal") }
                                Divider()
                                Button(role: .destructive) { Task { await chat.respond(card: card, result: ["choice": "deny"]) } } label: { Label("Deny", systemImage: "xmark") }
                            }
                    } else {
                        // No context menu on a password or question card: a long press on the
                        // secure field inside an empty menu was one more thing to go wrong.
                        PendingCardView(chat: chat, card: card)
                            .glassEffectID("dock", in: namespace)
                    }
                } else {
                    ComposerView(chat: chat, text: $text, quote: $quote, namespace: namespace)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .animation(.snappy, value: chat.firstCard?.id)
        .animation(.snappy, value: chat.banner)
    }
}

struct QueueStrip: View {
    @Bindable var chat: ChatSession
    @State private var editing: QueuedMessage?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Queued (\(chat.queue.count))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(chat.queue) { q in
                HStack {
                    Text(q.text).font(.subheadline).lineLimit(2)
                    Spacer()
                    Button { editing = q; draft = q.text } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                    Button(role: .destructive) { chat.removeQueued(q.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .alert("Edit queued message", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Message", text: $draft)
            Button("Save") { if let e = editing { chat.updateQueued(e.id, text: draft) }; editing = nil }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }
}

/// The floating chat header, built like the Messages one: a glass back circle, a centred pill with
/// the bot's avatar above the name (status while the agent works), and a glass … circle.
struct ChatHeader: View {
    @Bindable var chat: ChatSession
    /// The fold's frame in this header's coordinates when a partly open Duo has one here; the
    /// pill moves to the side of it with more room (nothing interactive sits on the fold).
    var fold: CGRect? = nil
    var showBack = true
    var onBack: () -> Void
    var onProfile: () -> Void
    var onRename: () -> Void
    var onContext: () -> Void
    var onNewChat: () -> Void
    var onClose: () -> Void
    @Environment(\.colorScheme) private var scheme
    /// The bot pops into the header the way a contact does in Messages.
    @State private var popped = false
    /// VoiceOver starts on Back when the chat opens, as it did while the header came first in
    /// the screen's order: it comes last now (see `ConversationView.header`), and the first
    /// element would otherwise be the oldest message laid out.
    @AccessibilityFocusState private var backFocused: Bool
    @AppStorage(ChatStyle.headerShowsTitle) private var headerShowsTitle = false
    /// The pill's frame and the header's width, for keeping the pill off the fold.
    @State private var pillFrame: CGRect = .zero
    @State private var headerWidth: CGFloat = 0
    /// Read here so a name saved on the bot's card (#315) redraws the header.
    @AppStorage(BotNames.storageKey) private var namesRaw = ""
    private var botLabel: String { _ = namesRaw; return chat.runtime.profiles.first { $0.name == chat.profileName }?.label ?? chat.profileName }
    private var headline: String { headerShowsTitle ? chat.title : botLabel }
    private var idleLine: String { headerShowsTitle ? chat.subtitle : (chat.title.count > 30 ? String(chat.title.prefix(29)) + "…" : chat.title) }

    var body: some View {
        // No glass container here: a container draws its glass on a layer above the rest, and
        // the pill covered the bot sitting on it.
        HStack(alignment: .top, spacing: 12) {
            if showBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("chat.back")
                .accessibilityFocused($backFocused)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            Button {
                // The bot on the pill turns for the tap as it does elsewhere, and the plate opens.
                BotAmbient.shared.tap(profile: chat.profileName)
                onProfile()
            } label: {
                // Seated on the pill by its base; while it asks (the "!"), it lifts clear so the
                // dot does not cover the name.
                VStack(spacing: chat.botState == .awaitingApproval ? 2 : -(9 + 52 * BotFace.seatDrop(BotAvatarStore.choice(for: chat.profileName).spec(hex: "").shape))) {
                    // The bot sits on the pill, its base a few points over the top edge (measured from
                    // the shape, not the frame), like a contact photo in Messages; it springs in from
                    // small on the first appearance.
                    BotAvatar(profile: chat.profileName, size: 52, active: chat.isRunning,
                              mood: BotFaceView.Mood(session: chat.storedID, state: chat.botState))
                        .opacity(popped ? 1 : 0)
                        .zIndex(1)
                        // The face's own tap gesture would swallow the tap before the button saw
                        // it; the whole plate, bot included, is one target.
                        .allowsHitTesting(false)
                    VStack(spacing: 1) {
                        HStack(spacing: 3) {
                            // Hug the text like Messages does; long titles are shortened in code rather
                            // than letting a max-width frame stretch the pill across the screen.
                            Text(headline.count > 26 ? String(headline.prefix(25)) + "…" : headline).font(.caption.weight(.semibold)).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        }
                        // Shortened in code like the title: a compaction notice runs to a full
                        // sentence, and the pill would stretch to the edges for it.
                        // While it works: the goal the on-device model wrote, else the step it is on.
                        let goal = chat.isRunning ? ChatGoals.shared.goal(for: chat.storedID) : nil
                        let status = chat.isRunning ? (goal ?? chat.statusLine ?? "Thinking…") : (chat.isResuming ? "Syncing…" : idleLine)
                        Text(status.count > 42 ? String(status.prefix(41)).trimmingCharacters(in: .whitespaces) + "…" : status)
                            .font(.caption2).lineLimit(1)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: chat.statusLine)
                            .animation(.snappy, value: goal)
                            .animation(.snappy, value: chat.botState == .awaitingApproval)
                    }
                    .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 6)
                    // Its full height, but never wider than the room between the circles: with
                    // larger text the lines end in "…" (a pill that kept its width pushed the back
                    // circle off the screen).
                    .fixedSize(horizontal: false, vertical: true)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Off the fold of a partly open Duo: to whichever side has more room.
            .offset(x: FoldAvoidance.offset(for: pillFrame, fold: fold, in: headerWidth))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("chatHeader")) } action: { pillFrame = $0 }
            // The pill is offered that room before the spacers beside it share what is left, so
            // it is cut short only when its text does not fit.
            .layoutPriority(1)
            .onAppear { withAnimation(.easeOut(duration: 0.25).delay(0.05)) { popped = true } }
            // A long press on the pill offers the rename; a tap opens the card as before.
            .contextMenu {
                Button(action: onRename) { Label("Rename chat", systemImage: "pencil") }
                Button(action: onProfile) { Label("Bot info", systemImage: "person.text.rectangle") }
            }
            .accessibilityLabel("Chat info: \(chat.title), \(chat.subtitle)")
            // The chat's title, as a navigation bar's is: the rotor's Headings reach the header
            // from anywhere in the thread.
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("chat.titlePill")
            Spacer(minLength: 0)
            Menu {
                ChatMenuItems(chat: chat, onProfile: onProfile, onRename: onRename, onContext: onContext, onNewChat: onNewChat, onClose: onClose)
            } label: {
                Image(systemName: "ellipsis").font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
            }
            .menuStyle(.button).buttonStyle(.plain)
            .accessibilityIdentifier("chat.more")
        }
        .padding(.horizontal, 16)
        .coordinateSpace(.named("chatHeader"))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { headerWidth = $0 }
        .padding(.top, 4)
        // The bar is one surface, like the Messages header: a tap anywhere on it stays on it and
        // never reaches the thread scrolling underneath (a tool card would otherwise expand).
        .contentShape(.rect)
        .onTapGesture {}
        // Once the push has settled: VoiceOver moves to the new screen's first element when the
        // transition ends, and would take over a request made before it.
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            backFocused = true
        }
    }
}

/// The … menu's items, shared by the iOS header's glass circle and the Mac toolbar's button.
struct ChatMenuItems: View {
    @Bindable var chat: ChatSession
    var onProfile: () -> Void
    var onRename: () -> Void
    var onContext: () -> Void
    var onNewChat: () -> Void
    var onClose: () -> Void

    var body: some View {
        Menu {
            ModelMenuContent(chat: chat)
        } label: { Label("Model: \(chat.modelName.isEmpty ? "none" : (chat.modelName.split(separator: "/").last.map(String.init) ?? chat.modelName))", systemImage: "cpu") }
        ReasoningEffortMenu(chat: chat)
        Button(action: onContext) { Label("Context usage\(chat.usage?.computedContextPercent.map { " · \($0)%" } ?? "")", systemImage: "gauge.with.dots.needle.33percent") }
        Button(action: onProfile) { Label("Bot info", systemImage: "person.text.rectangle") }
        Button(action: onRename) { Label("Rename chat", systemImage: "pencil") }
        Button { HandsFreeSession.shared.start(chat: chat) } label: { Label("Voice mode", systemImage: "waveform.badge.mic") }
        #if os(iOS)
        // The newest finished reply read aloud, as the Mac's Chat menu has it; again stops it.
        if let last = VoiceCoordinator.lastReply(in: chat.items) {
            Button { VoiceCoordinator.shared.toggleSpeaking(last) } label: {
                Label(VoiceCoordinator.shared.isSpeaking(last) ? "Stop Speaking" : "Speak Last Reply", systemImage: VoiceCoordinator.shared.isSpeaking(last) ? "stop.circle" : "speaker.wave.2")
            }
            .disabled(HandsFreeSession.shared.isActive)
        }
        #endif
        ChatProjectMenu(chat: chat)
        Divider()
        Button(action: onNewChat) { Label("New Chat", systemImage: "square.and.pencil") }
        Button { Task { await chat.loadUsage() } } label: { Label("Refresh usage", systemImage: "arrow.clockwise") }
        Divider()
        Button(role: .destructive, action: onClose) { Label("Close session", systemImage: "xmark.circle") }
    }
}

#if os(macOS)
/// The Mac has no pop gesture to put back; the chat sits in the split view's detail column.
struct InteractivePopEnabler: View {
    var body: some View { Color.clear }
}
#else
/// Re-enables the navigation controller's interactive pop gesture while its bar is hidden, and
/// lets it start anywhere on the screen (not only at the left edge) for one-handed use: a pan
/// recognizer on the navigation view drives the same targets as the edge gesture. Put one under
/// each tab's root page (and under a page that hides the bar); a stack gets exactly one pan,
/// owned by a delegate that lives as long as the stack does. (Earlier each pushed chat added its
/// own pan and left it behind with a dead delegate, so after a few chats a stack carried several
/// pans that began on ANY drag: threads that slid both ways, and no time reveal.)
struct InteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ c: Controller, context: Context) { c.enable() }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); enable() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); enable() }
        func enable() {
            guard let nav = navigationController ?? parent?.navigationController else { return }
            FullScreenPop.install(on: nav)
        }
    }
}

/// The one full-screen back pan of a navigation stack and the delegate for both it and the
/// system's edge gesture; kept alive on the navigation controller itself.
final class FullScreenPop: NSObject, UIGestureRecognizerDelegate {
    private static var key = 0
    private weak var nav: UINavigationController?
    private weak var pan: UIPanGestureRecognizer?
    /// The back swipe's progress for whoever draws along with it (RootView's tab bar): the
    /// fraction, and whether this is the end (then the fraction is 0 for a cancelled swipe or
    /// 1 for a completed one, to be animated over `duration`).
    nonisolated(unsafe) static var onProgress: ((_ fraction: CGFloat, _ ended: Bool, _ duration: Double) -> Void)?
    private var tracking = false
    /// The stack's depth when the swipe began: a pop that has already finished by the time
    /// the finger lifts (a quick flick) shows as one controller fewer.
    private var depthAtBegin = 0

    @objc private func track(_ g: UIPanGestureRecognizer) {
        guard let nav, let view = g.view else { return }
        switch g.state {
        case .began, .changed:
            guard nav.transitionCoordinator?.isInteractive == true || g.state == .began else { return }
            if !tracking { Perf.stamp("pop: swipe began"); depthAtBegin = nav.viewControllers.count }
            tracking = true
            let fraction = max(0, min(1, g.translation(in: view).x / max(1, view.bounds.width)))
            Self.onProgress?(fraction, false, 0)
        case .ended, .cancelled, .failed:
            guard tracking else { return }
            tracking = false
            Perf.stamp("pop: swipe released")
            if let c = nav.transitionCoordinator {
                let duration = c.transitionDuration
                let remaining = { (ctx: UIViewControllerTransitionCoordinatorContext) in max(0.15, duration * (1 - Double(ctx.percentComplete))) }
                if c.isInteractive {
                    c.notifyWhenInteractionChanges { ctx in
                        Perf.stamp("pop: interaction ended cancelled=\(ctx.isCancelled) at \(ctx.percentComplete)")
                        Self.onProgress?(ctx.isCancelled ? 0 : 1, true, remaining(ctx))
                    }
                } else {
                    // The system's own handler ran first and has already decided the end.
                    Perf.stamp("pop: swipe end decided cancelled=\(c.isCancelled) at \(c.percentComplete)")
                    Self.onProgress?(c.isCancelled ? 0 : 1, true, remaining(c))
                }
                c.animate(alongsideTransition: nil) { ctx in Perf.stamp("pop: transition completed cancelled=\(ctx.isCancelled)") }
            } else {
                // No transition left: a flick that has already popped, or a pan that never did.
                let popped = nav.viewControllers.count < depthAtBegin
                Perf.stamp("pop: swipe ended with no transition, popped=\(popped)")
                Self.onProgress?(popped ? 1 : 0, true, 0.2)
            }
        default: break
        }
    }

    static func install(on nav: UINavigationController) {
        guard let edge = nav.interactivePopGestureRecognizer else { return }
        edge.isEnabled = true
        if let existing = objc_getAssociatedObject(nav, &key) as? FullScreenPop {
            edge.removeTarget(existing, action: #selector(track(_:))); edge.addTarget(existing, action: #selector(track(_:)))
            edge.delegate = existing
            if existing.pan == nil || existing.pan?.view == nil { existing.addPan(edge: edge) }
            return
        }
        let d = FullScreenPop()
        d.nav = nav
        objc_setAssociatedObject(nav, &key, d, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        edge.delegate = d
        edge.addTarget(d, action: #selector(track(_:)))
        d.addPan(edge: edge)
    }

    private func addPan(edge: UIGestureRecognizer) {
        guard let nav, let targets = edge.value(forKey: "targets") as? NSArray, targets.count > 0 else { return }
        // Never two on one view (a stack re-created around the same controller, say).
        nav.view.gestureRecognizers?.filter { $0.name == "vory.fullScreenPop" }.forEach { nav.view.removeGestureRecognizer($0) }
        let pan = UIPanGestureRecognizer()
        pan.name = "vory.fullScreenPop"
        pan.setValue(targets, forKey: "targets")
        pan.addTarget(self, action: #selector(track(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        nav.view.addGestureRecognizer(pan)
        self.pan = pan
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let nav, nav.viewControllers.count > 1 else { return false }
        guard let pan = g as? UIPanGestureRecognizer, g === self.pan else { return true }
        // A row of a list keeps its own swipe (the Board's Done and Unblock are a leading swipe,
        // which this pan ate on a Board pushed from Settings); the edge gesture still goes back there.
        if let hit = pan.view?.hitTest(pan.location(in: pan.view), with: nil), Self.isInListRow(hit) { return false }
        // Only a clear rightward, mostly horizontal drag; vertical scrolling and the leftward
        // time-reveal drag in the thread are left alone.
        let v = pan.velocity(in: pan.view)
        return v.x > 250 && abs(v.x) > abs(v.y) * 1.8
    }

    private static func isInListRow(_ view: UIView) -> Bool {
        var v: UIView? = view
        while let x = v {
            if x is UICollectionViewListCell || x is UITableViewCell { return true }
            v = x.superview
        }
        return false
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
}
#endif

/// Unsent composer text, per session, so leaving a chat and coming back does not lose it.
/// What a chat's views had when they went away and get back when they return: the composer's
/// keyboard focus and the thread's distance from its end. A layout switch (the open Duo turned
/// upright or back: one column to two) rebuilds the chat's views; the open chat is in
/// `AppModel.chatPath`, the draft in `ComposerDrafts`, and these two are the rest of what the
/// person had under their hands. In memory only, for the app's run.
@MainActor enum ChatViewMemory {
    static func key(for chat: ChatSession) -> String { chat.storedID ?? chat.runtimeID }
    private(set) static var focused: Set<String> = []
    private(set) static var distanceFromEnd: [String: CGFloat] = [:]
    static func setFocused(_ on: Bool, for chat: ChatSession) { if on { focused.insert(key(for: chat)) } else { focused.remove(key(for: chat)) } }
    static func setDistanceFromEnd(_ d: CGFloat?, for chat: ChatSession) { distanceFromEnd[key(for: chat)] = d }
}

@MainActor
enum ComposerDrafts {
    private static func key(for chat: ChatSession) -> String { "composerDraft." + (chat.storedID ?? chat.runtimeID) }

    static func load(for chat: ChatSession) -> String? {
        let t = UserDefaults.standard.string(forKey: key(for: chat)) ?? ""
        return t.isEmpty ? nil : t
    }

    static func save(_ text: String, for chat: ChatSession) {
        // Only a write that changes something: every defaults write re-runs the views that read
        // defaults (the chat list's filters), and an empty draft was written on every Back.
        let k = key(for: chat)
        let stored = UserDefaults.standard.string(forKey: k)
        if text.isEmpty { if stored != nil { UserDefaults.standard.removeObject(forKey: k) } }
        else if stored != text { UserDefaults.standard.set(text, forKey: k) }
    }
}
