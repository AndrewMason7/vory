import SwiftUI
import VoryCore
import WatchKit

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            Group {
                if model.runtime != nil { WatchChatsView(path: $path) }
                else { WatchConnectView() }
            }
            .navigationDestination(for: String.self) { WatchChatView(storedID: $0) }
            .navigationDestination(for: WatchActivityRoute.self) { _ in WatchActivityView(path: $path) }
            .navigationDestination(for: WatchOverviewRoute.self) { _ in WatchOverviewView() }
        }
        .onChange(of: model.pendingOverview) { _, go in
            if go { path = NavigationPath(); path.append(WatchOverviewRoute()); model.pendingOverview = false }
        }
        .onChange(of: model.pendingChat) { _, id in
            if let id { path.append(id); model.pendingChat = nil }
        }
        .onChange(of: model.pendingActivity) { _, go in
            if go { path = NavigationPath(); path.append(WatchActivityRoute()); model.pendingActivity = false }
        }
    }
}

struct WatchActivityRoute: Hashable {}
struct WatchOverviewRoute: Hashable {}

/// Home's overview on the wrist: the week and the month in numbers and the activity blocks,
/// from the same snapshot the complications draw. Opens at once with what is stored.
struct WatchOverviewView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let u = model.usage {
                    HStack(alignment: .top) {
                        stat("\(u.sessions7)", "chats, 7d")
                        stat(WidgetSnapshot.Usage.tokens(u.tokens7), "tokens, 7d")
                    }
                    UsageBlocks(days: u.days, weeks: nil)
                        .frame(height: 62)
                        .accessibilityLabel("Activity blocks, one per day")
                    HStack(alignment: .top) {
                        stat("\(u.sessions30)", "chats, 30d")
                        stat("\(u.activeDays30)", "active days")
                    }
                    if let m = u.topModel { Label(m, systemImage: "cpu").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    Text("Updated \(u.updatedAt, style: .relative) ago").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("No numbers yet. They arrive from the gateway's analytics.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
        .task { await model.loadUsage() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What the complications open to: the chats waiting for an answer and the ones at work, with
/// the gateway's state on top. A row opens its chat.
struct WatchActivityView: View {
    @Environment(WatchModel.self) private var model
    @Binding var path: NavigationPath

    var body: some View {
        List {
            if let rt = model.runtime {
                let waiting = model.sessions.filter { rt.needsAttention.contains($0.id) }
                let working = model.sessions.filter { !rt.needsAttention.contains($0.id) && (rt.chatForStored($0.id)?.isRunning == true || $0.isActive == true) }
                Section {
                    HStack(spacing: 6) {
                        Circle().fill(model.socketUsable ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(rt.connection.name).font(.headline).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(model.socketUsable ? "Online" : "Via iPhone").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("\(waiting.count) need you", systemImage: "exclamationmark.bubble.fill").foregroundStyle(waiting.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        Spacer()
                        Label("\(working.count) working", systemImage: "ellipsis.message.fill").foregroundStyle(working.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                    }
                    .font(.caption2)
                }
                Section("Needs you") {
                    if waiting.isEmpty { Text("Nothing waiting").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(waiting) { s in NavigationLink(value: s.id) { WatchSessionRow(session: s, badge: "exclamationmark.bubble.fill", showBot: true) } }
                }
                Section("Working") {
                    if working.isEmpty { Text("No chat is working right now").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(working) { s in NavigationLink(value: s.id) { WatchSessionRow(session: s, badge: "ellipsis.message", showBot: true) } }
                }
            }
        }
        .navigationTitle("Activity")
        .refreshable { await model.loadSessions() }
        .task { await model.loadSessions() }
    }
}

/// The bot's face on the watch: the look the iPhone sent (shape, eyes, colour, or a photo),
/// drawn still. Falls back to the default shape in the bot's palette colour.
struct WatchBotFace: View {
    @Environment(WatchModel.self) private var model
    var profile: String
    var label: String? = nil
    var size: CGFloat = 24

    var body: some View {
        let looks = model.looks
        let key = looks.key(profile: profile, label: label ?? "") ?? profile
        if looks.avatars[key] == "photo", let data = looks.photos[key], let img = WatchPhotoCache.image(key: key, data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: size, height: size).clipShape(.circle)
        } else {
            let hex = looks.colors[key] ?? WatchBotColor.hex(for: profile)
            BotFaceView(spec: BotLookSpec.from(choice: looks.avatars[key], hex: hex), size: size, active: false, drawn: true)
                .frame(width: size, height: size)
        }
    }
}

/// A bot's photo, decoded once: a list of chats used to decode the same JPEG for every row on
/// every redraw.
@MainActor
enum WatchPhotoCache {
    private static var images: [String: (bytes: Int, image: UIImage)] = [:]
    static func image(key: String, data: Data) -> UIImage? {
        if let hit = images[key], hit.bytes == data.count { return hit.image }
        guard let img = UIImage(data: data) else { return nil }
        images[key] = (data.count, img)
        return img
    }
}

/// Recent sessions, with the ones waiting for you on top.
struct WatchChatsView: View {
    @Environment(WatchModel.self) private var model
    @Binding var path: NavigationPath
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showNewChat = false

    var body: some View {
        List {
            if let rt = model.runtime {
                let merged = model.listProfile == "*"
                let waiting = model.sessions.filter { rt.needsAttention.contains($0.id) }
                if !waiting.isEmpty {
                    Section("Needs you") {
                        ForEach(waiting) { s in NavigationLink(value: s.id) { WatchSessionRow(session: s, badge: "exclamationmark.bubble.fill", showBot: merged) } }
                    }
                }
                Section {
                    // One row for the three ways out of the list, so the chats start on the
                    // first screen instead of under three full-width rows.
                    HStack(spacing: 6) {
                        Button { showNewChat = true } label: { Image(systemName: "square.and.pencil").frame(maxWidth: .infinity) }
                            .accessibilityLabel("New chat")
                        Button { path.append(WatchActivityRoute()) } label: { Image(systemName: "bolt.horizontal.circle").frame(maxWidth: .infinity) }
                            .accessibilityLabel("Activity")
                        Button { path.append(WatchOverviewRoute()) } label: { Image(systemName: "square.grid.3x3.fill").frame(maxWidth: .infinity) }
                            .accessibilityLabel("Overview")
                    }
                    .buttonStyle(.bordered)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    ForEach(model.sessions.filter { !rt.needsAttention.contains($0.id) }) { s in
                        NavigationLink(value: s.id) { WatchSessionRow(session: s, badge: rt.chatForStored(s.id)?.isRunning == true ? "ellipsis.message" : nil, showBot: merged) }
                    }
                    if model.hasMore {
                        // A few chats load first; this brings the next page as you scroll down.
                        Button { Task { await model.loadMore() } } label: {
                            if model.loadingMore { Label { Text("Loading…") } icon: { ProgressView() } }
                            else { Label("Show more", systemImage: "arrow.down.circle") }
                        }
                        .disabled(model.loadingMore)
                        .onAppear { Task { await model.loadMore() } }
                    }
                } header: {
                    if merged { Text("All bots") }
                    else {
                        let p = model.listProfile ?? rt.selectedProfile ?? ""
                        HStack(spacing: 6) {
                            if !p.isEmpty { WatchBotFace(profile: p, label: rt.profiles.first { $0.name == p }?.label, size: 18) }
                            Text(p.isEmpty ? rt.connection.name : (rt.profiles.first { $0.name == p }?.label ?? p))
                        }
                    }
                }
                if let e = model.loadError { Text(e).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Vory")
        .toolbar {
            if model.runtime != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicker = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Choose bot")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showPicker) { WatchProfilePicker() }
        .sheet(isPresented: $showSettings) { WatchSettingsView() }
        .sheet(isPresented: $showNewChat) {
            WatchNewChatSheet { profile in
                showNewChat = false
                Task { await newChat(profile: profile) }
            }
        }
        .refreshable { await model.loadSessions() }
        .task { await model.loadSessions() }
    }

    private func newChat(profile: String) async {
        guard let rt = model.runtime else { return }
        rt.selectedProfile = profile
        if model.listProfile != "*" { model.listProfile = profile }
        if model.socketUsable, let chat = try? await rt.newChat() { path.append(chat.storedID); return }
        // No direct socket (Bluetooth to the phone): ask the phone app to create it.
        do {
            let r = try await model.askPhone(["op": "new", "profile": profile])
            if let sid = r["session"] as? String, !sid.isEmpty { path.append(sid) }
            else { model.loadError = r["error"] as? String ?? "The phone could not create a chat." }
        } catch { model.loadError = "New chat needs the iPhone nearby: \(error.localizedDescription)" }
    }
}

/// New chat: the bots as a scrolling list, like the Bots page on the phone. Pick one and the
/// chat opens with it.
struct WatchNewChatSheet: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let rt = model.runtime {
                    ForEach(rt.profiles) { p in
                        Button { onPick(p.name) } label: {
                            HStack(spacing: 10) {
                                WatchBotFace(profile: p.name, label: p.label, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.label).font(.headline).lineLimit(1)
                                    if let m = p.model?.split(separator: "/").last { Text(String(m)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if rt.profiles.isEmpty { Text("No bots yet. Open Vory on the iPhone once.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("New chat")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Pick which bot's chats the list shows, or all of them merged (watchOS has no Menu).
struct WatchProfilePicker: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Button { model.listProfile = "*"; Task { await model.loadSessions() }; dismiss() } label: {
                Label("All bots", systemImage: "person.2")
            }
            if let rt = model.runtime {
                ForEach(rt.profiles) { p in
                    Button { model.listProfile = p.name; rt.selectedProfile = p.name; Task { await model.loadSessions() }; dismiss() } label: {
                        HStack(spacing: 8) {
                            WatchBotFace(profile: p.name, label: p.label, size: 26)
                            Text(p.label)
                            Spacer()
                            if (model.listProfile ?? rt.selectedProfile) == p.name { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bots")
    }
}

/// The same deterministic palette the phone uses when no colour was picked for a bot: the
/// phone's list itself, from VoryCore (a copy here had every colour off by a digit).
enum WatchBotColor {
    static func hex(for profile: String) -> String { BotPalette.defaultHex(for: profile) }
    static func color(for profile: String) -> Color { Color(botHex: hex(for: profile)) ?? .accentColor }
}

struct WatchSessionRow: View {
    @Environment(WatchModel.self) private var model
    var session: StoredSession
    var badge: String?
    var showBot = false
    var body: some View {
        let summary = model.summary(for: session)
        HStack(spacing: 8) {
            if showBot { WatchBotFace(profile: session.profile ?? "?", size: 24) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if session.pinned == true { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                    Text(summary?.title ?? session.displayTitle).font(.headline).lineLimit(2)
                }
                Text(summary?.summary ?? session.preview ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(summary == nil ? 1 : 2)
            }
            Spacer(minLength: 0)
            if let badge { Image(systemName: badge).foregroundStyle(badge.hasPrefix("exclamation") ? .orange : .green) }
        }
    }
}

/// One chat: the tail of the transcript, the card when one is waiting, and a composer pinned to the bottom edge so the
/// thread opens at its end. Its data and the one thing that drives it are the chat's feed (`WatchChatFeed`, #387): on
/// the Watch's own socket or through the iPhone, read when something changed rather than every few seconds. The view
/// only shows the feed and acts through it; the wrist buzzes only for the feed's arrivals (`WatchChatFeed.event`).
struct WatchChatView: View {
    @Environment(WatchModel.self) private var model
    var storedID: String
    @State private var feed: WatchChatFeed?
    @State private var text = ""
    /// Talk: a recording to the gateway, the reply read aloud here.
    @State private var talk = WatchTalk()
    /// What Talk could not do, under the thread until tapped.
    @State private var talkNote: String?
    /// The bottom bar's top edge and the thread's bottom edge, on screen: the room the thread leaves under its last row
    /// (brief points 1 and 4: the conversation ends above the composer, never under it).
    @State private var barTop: CGFloat = 0
    @State private var threadBottom: CGFloat = 0
    /// The person moved the thread (a scroll, Show earlier) since the first read landed: the late settle leaves it.
    @State private var movedByPerson = false

    var body: some View {
        Group {
            if let feed { thread(feed) } else { ProgressView() }
        }
        // Leaving the chat ends Talk's wait and voice: the reply would otherwise be read out later with no screen to
        // stop it from.
        .onDisappear { talk.stopWaiting(); talk.stopSpeaking() }
        // A feed of its own for each runtime (a new route or address): the old one ends with its task.
        .task(id: model.runtime.map(ObjectIdentifier.init)) {
            let f = WatchChatFeed(storedID: storedID, model: model)
            feed = f
            await f.run()
        }
    }

    private func thread(_ feed: WatchChatFeed) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if feed.hasEarlier {
                        // The last few messages first; the rest a page at a time from the top.
                        Button { movedByPerson = true; Task { await feed.loadEarlier() } } label: { Label("Show earlier", systemImage: "arrow.up.circle") }.font(.caption)
                    }
                    ForEach(feed.items) { item in WatchTranscriptRow(item: item, profile: feed.profile).id(item.id) }
                    if feed.isWorking { Text(Self.workingLine(feed)).font(.caption2).foregroundStyle(.secondary) }
                    // What went wrong (a send that did not get through, the iPhone out of reach, a Talk that heard nothing).
                    if let p = feed.problem { Text(p.text).font(.caption2).foregroundStyle(.red).onTapGesture { feed.dismissProblem() } }
                    if let talkNote { Text(talkNote).font(.caption2).foregroundStyle(.red).onTapGesture { self.talkNote = nil } }
                    if let card = feed.cards.first { WatchCardView(feed: feed, card: card).id(card.id) }
                    // Room for the bottom bar under the last row, the bar's own height as measured: the bar is laid over
                    // the content, and the last lines (or a card's buttons) ran under it. With the bar gone for a card,
                    // a little room for the screen's rounded edge.
                    Color.clear.frame(height: barShown(feed) ? max(8, threadBottom - barTop + 6) : 8).id("bottom")
                }
            }
            // The thread opens on its end and sits at the bottom when short. As it changes size it keeps its end in
            // view, but while a card waits it keeps its top: the bar giving way to the card changed the size, and held by
            // the end, the card slid back to its last two choices with the ask and Allow once out of sight.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .defaultScrollAnchor(feed.cards.isEmpty ? .bottom : .top, for: .sizeChanges)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { threadBottom = $0 }
            .onScrollPhaseChange { _, phase in if phase == .interacting { movedByPerson = true } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            // The first read lands after the view does: land the end again once it is in, and once more when its rows have
            // been laid out. At the largest text the lazy stack placed the first scroll on its estimates of the tall rows,
            // past the content, and the chat opened blank (41 mm, ax); the view before the feed settled it the same way.
            // Restores the settle the view had before the feed (range B dropped it); after the first read only.
            .onChange(of: feed.isLoading) { _, loading in
                guard !loading else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
                movedByPerson = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    // Not over the person's own move in the meantime, nor over a card that came (it lands itself).
                    if !movedByPerson, feed.cards.isEmpty { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: feed.event) { _, event in arrived(event, proxy) }
            .navigationTitle(feed.title)
            .toolbar {
                // The bottom bar is where watchOS pins a field to the screen's bottom edge; a safe-area inset sat above
                // a blank band on the Ultra. It gives way to a card (`barShown`).
                if barShown(feed) {
                ToolbarItem(placement: .bottomBar) {
                    composer(feed) {
                        let t = text; text = ""
                        do {
                            try await feed.send(t)
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        } catch { text = t }
                    }
                }
                }
                if feed.isWorking {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { talk.stopWaiting(); Task { await feed.stop() } } label: { Image(systemName: "stop.fill") }.tint(.red)
                    }
                }
            }
        }
    }

    /// The feed's arrivals, each once while the chat is open: the only haptics here, and a scroll to what arrived. A
    /// first read, a wrist raise's read of what was already seen and a switch between the socket and the iPhone have
    /// none (the feed's gate), where the old view buzzed and jumped on every read.
    private func arrived(_ event: WatchFeedEvent?, _ proxy: ScrollViewProxy) {
        guard let event else { return }
        switch event.kind {
        case .replyArrived(let id):
            WKInterfaceDevice.current().play(.success)
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        case .cardArrived(let id):
            WKInterfaceDevice.current().play(.notification)
            // From its top: the ask and Allow once first. A card is taller than the Watch's screen, and landed by its
            // bottom it showed only the last two choices, the ask and Allow once out of sight above. Again once the bar
            // has given way to it (`barShown`), unless the person has moved the thread since.
            withAnimation { proxy.scrollTo(id, anchor: .top) }
            movedByPerson = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if !movedByPerson { withAnimation { proxy.scrollTo(id, anchor: .top) } }
            }
        case .turnFailed:
            WKInterfaceDevice.current().play(.failure)
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    /// "Working…", the gateway's own words when it has some, and how many steps this turn has taken.
    private static func workingLine(_ feed: WatchChatFeed) -> String {
        let steps = feed.turnTools.count
        let line = feed.statusLine?.isEmpty == false ? feed.statusLine! : "Working…"
        return steps == 0 ? line : "\(line) · \(steps) \(steps == 1 ? "step" : "steps")"
    }

    /// Talk's and Send's hit area: a finger's worth, where the glyph alone was 19 pt.
    private static let buttonSide: CGFloat = 30

    /// While a card waits the bottom bar gives way to it, as the iPhone's dock turns into the card: laid over the
    /// content, the field and Talk covered the card's Allow once at the largest text (41 mm, ax). The bar comes back
    /// with the answer, the draft kept; it stays while Talk is at work, so a recording can still be stopped (the
    /// planner, 2026-10-20).
    private static let barGivesWayToCards = true

    private func barShown(_ feed: WatchChatFeed) -> Bool {
        !(Self.barGivesWayToCards && !feed.cards.isEmpty && !talk.isBusy)
    }

    /// The message field, Talk and the send button, one row on the bottom edge. While Talk works the row says what it is
    /// doing instead of the field.
    private func composer(_ feed: WatchChatFeed, send: @escaping () async -> Void) -> some View {
        composerRow(feed, send: send)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { barTop = $0 }
    }

    private func composerRow(_ feed: WatchChatFeed, send: @escaping () async -> Void) -> some View {
        HStack(spacing: 6) {
            if talk.isBusy {
                Text(talk.phaseText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                TextField("Message", text: $text)
                    .accessibilityIdentifier("watch.chat.message")
            }
            // Talk on the live chat, or through the iPhone when this chat is on the phone path.
            if let target = feed.talkTarget {
                // While the reply is awaited the same button gives the wait up (the reply still lands in the chat).
                Button { talk.tap(target: target) } label: {
                    Image(systemName: talk.phase == .recording ? "stop.circle.fill" : talk.phase == .speaking ? "speaker.slash.circle.fill" : talk.phase == .waiting ? "xmark.circle.fill" : "mic.circle.fill")
                        .font(.title3)
                        .symbolEffect(.pulse, isActive: talk.phase == .recording || talk.phase == .waiting)
                        // A finger's worth to hit, not the 19 pt glyph alone.
                        .frame(width: Self.buttonSide, height: Self.buttonSide)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(talk.phase == .recording ? Color.red : talk.isBusy ? Color.accentColor : Color.secondary)
                .disabled(talk.phase == .transcribing)
                .accessibilityLabel(talk.phase == .recording ? "Stop and send" : talk.phase == .speaking ? "Stop speaking" : talk.phase == .waiting ? "Stop waiting for the reply" : "Talk")
            }
            if !talk.isBusy {
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title3)
                        .frame(width: Self.buttonSide, height: Self.buttonSide)
                        .contentShape(.circle)
                }
                    .buttonStyle(.plain).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.accentColor)
                    // VoiceOver read the glyph's name ("Arrow Up Circle").
                    .accessibilityLabel("Send")
            }
        }
        .onChange(of: talk.error) { _, e in
            guard let e else { return }
            talkNote = e
            talk.error = nil
        }
    }
}

struct WatchTranscriptRow: View {
    var item: TranscriptItem
    /// The bot the reply came from: a small face beside each reply, as on the phone.
    var profile: String? = nil
    var body: some View {
        switch item.kind {
        case .user(let t, _):
            if let notice = WatchNotice.parse(t) {
                // Another bot writing in, or the gateway reporting: a quiet line, not your own bubble.
                VStack(alignment: .leading, spacing: 2) {
                    Label(notice.title, systemImage: notice.symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if !notice.body.isEmpty { Text(notice.body).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
                }
            } else {
                HStack { Spacer(minLength: 24); Text(t).font(.footnote).padding(8).background(Color.accentColor, in: .rect(cornerRadius: 12)).foregroundStyle(.white) }
            }
        case .assistant(let raw, _, let streaming):
            // Pictures the bot sent are names here, not paths: the MEDIA: line stays out.
            let t = MediaScan.textWithoutMedia(raw)
            HStack(alignment: .bottom, spacing: 4) {
                if let profile { WatchBotFace(profile: profile, size: 16).accessibilityHidden(true) }
                // Bold, italics, code and links once the reply is whole; plain while it streams.
                Group {
                    if streaming { Text(t.isEmpty ? "…" : t) } else { Text(WatchMarkdown.inline(t)) }
                }
                .font(.footnote).padding(8).background(Color.gray.opacity(0.25), in: .rect(cornerRadius: 12))
                Spacer(minLength: 12)
            }
        case .tool(let a):
            Label("\(a.displayName)\(a.summary.map { " · \($0)" } ?? "")", systemImage: a.status == .done ? "checkmark.circle" : a.status == .failed ? "xmark.circle" : "gear")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        case .system(let t, let sym):
            Label(t, systemImage: sym).font(.caption2).foregroundStyle(.secondary)
        case .error(let t):
            Label(t, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.red)
        case .subagent(let a):
            Label(a.detailLine.map { "\(a.goal) · \($0)" } ?? a.goal, systemImage: "person.2").font(.caption2).foregroundStyle(.secondary)
        case .steer(let t, _):
            Text(t).font(.caption).padding(6).background(Color.gray.opacity(0.3), in: .rect(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// A message in the user's seat that is not the user's: another bot, or the gateway.
struct WatchNotice {
    var title: String
    var body: String
    var symbol: String

    /// Cheap checks first: almost every message is an ordinary one.
    static func parse(_ text: String) -> WatchNotice? {
        let t = text.drop { $0 == " " || $0 == "\n" }
        if t.hasPrefix("Message from") || t.hasPrefix("[Message from agent") {
            if let m = AgentMessage.parse(text) { return WatchNotice(title: "Message from \(m.sender)", body: m.body, symbol: "bubble.left.and.bubble.right") }
        } else if t.hasPrefix("[") {
            if let n = InjectedNote.parse(text) { return WatchNotice(title: n.title, body: "", symbol: "gearshape.2") }
        }
        return nil
    }
}

/// Inline markdown for finished replies, parsed once per text.
@MainActor
enum WatchMarkdown {
    private static var cache: [Int: AttributedString] = [:]

    static func inline(_ text: String) -> AttributedString {
        let key = text.hashValue
        if let hit = cache[key] { return hit }
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(text)
        if cache.count > 80 { cache.removeAll(keepingCapacity: true) }
        cache[key] = parsed
        return parsed
    }
}

/// Approval / clarify / secret cards, sized for a wrist, answered through the chat's feed on either path (#387).
/// An approval's two common answers are big (Allow once in green, Deny in red) and the other two the gateway offers sit
/// smaller under them, with the names the iPhone uses (judgement call #36); "Always allow…" asks first, as there.
struct WatchCardView: View {
    var feed: WatchChatFeed
    var card: PendingCard
    @State private var answer = ""
    @State private var sending = false
    @State private var failed: String?
    @State private var confirmAlways = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = card.approval {
                Label("Approval", systemImage: "checkmark.shield").font(.caption.weight(.semibold))
                Text(a.description?.isEmpty == false ? a.description! : (a.command ?? "")).font(.footnote).lineLimit(6)
                let offered = a.offeredChoices
                if offered.contains("once") {
                    Button { choose("once") } label: { Text("Allow once").frame(maxWidth: .infinity) }.tint(.green)
                }
                if offered.contains("deny") {
                    Button(role: .destructive) { choose("deny") } label: { Text("Deny").frame(maxWidth: .infinity) }.tint(.red)
                }
                if offered.contains("session") {
                    Button("Allow for this chat") { choose("session") }.font(.caption)
                }
                if offered.contains("always") {
                    Button("Always allow…") { confirmAlways = true }.font(.caption)
                        .alert("Always allow \(a.alwaysScope)?", isPresented: $confirmAlways) {
                            Button("Always allow") { choose("always") }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Every chat with this bot runs it without asking, until the rule is removed on the iPhone.")
                        }
                }
            } else if let c = card.clarify {
                Label("Question", systemImage: "questionmark.bubble").font(.caption.weight(.semibold))
                Text(c.question ?? c.questions?.first?.question ?? "").font(.footnote)
                // Offered answers are buttons: one tap, no typing on the wrist.
                ForEach((c.choices ?? c.questions?.first?.choices ?? []).prefix(6), id: \.self) { choice in
                    Button(choice) { choose(choice) }.font(.footnote)
                }
                TextField("Answer", text: $answer)
                Button("Send") { reply(answer) }.disabled(answer.isEmpty)
            } else {
                Label("Input needed", systemImage: "key").font(.caption.weight(.semibold))
                Text(card.valuePrompt?.prompt ?? card.method).font(.footnote)
                SecureField("Value", text: $answer)
                Button("Send") { reply(answer) }.disabled(answer.isEmpty)
            }
            if let failed { Text(failed).font(.caption2).foregroundStyle(.red) }
        }
        .disabled(sending)
        .padding(10)
        .background(.orange.opacity(0.15), in: .rect(cornerRadius: 14))
    }

    /// An approval by the gateway's choice key, or a question by one of its offered answers.
    private func choose(_ choice: String) {
        act { try await feed.answer(card, choice: choice) }
    }

    private func reply(_ text: String) {
        act { try await feed.answer(card, text: text) }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        sending = true; failed = nil
        Task {
            do { try await work() } catch { failed = error.localizedDescription }
            sending = false
        }
    }
}

/// Before a gateway is known: normally the phone pushes it over; a token can be typed if not.
struct WatchConnectView: View {
    @Environment(WatchModel.self) private var model
    @State private var url = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "iphone.and.applewatch").font(.largeTitle).foregroundStyle(.tint)
                Text("Open Vory on your iPhone").font(.headline)
                Text(model.syncStatus).font(.caption2).foregroundStyle(.secondary)
                Text("Your gateways sync here automatically. Or enter one by hand:").font(.caption2).foregroundStyle(.secondary)
                TextField("https://hermes.example.com", text: $url).textContentType(.URL)
                SecureField("Session token", text: $token)
                Button(busy ? "Connecting…" : "Connect") { Task { await connect() } }.disabled(busy || url.isEmpty || token.isEmpty)
                if let error { Text(error).font(.caption2).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Vory")
    }

    private func connect() async {
        busy = true; defer { busy = false }
        do {
            let g = try GatewayURL.normalize(url, pathPrefix: nil)
            let conn = GatewayConnection(name: g.host, gateway: g, authMode: .sessionToken)
            try model.store.upsert(conn, secrets: GatewaySecrets(sessionToken: token))
            await model.activate(conn)
        } catch { self.error = error.localizedDescription }
    }
}

/// A small settings pane: which gateway, how the watch reaches it, and a way to re-pull the
/// credentials from the phone.
struct WatchSettingsView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let rt = model.runtime {
                    Section("Gateway") {
                        LabeledContent("Name", value: rt.connection.name)
                        LabeledContent("Link", value: model.socketUsable ? "Direct, live" : model.throughPhone ? "Through iPhone" : "Direct")
                        if model.route != .relayOnly { LabeledContent("Status", value: rt.socketState.label) }
                        LabeledContent("Bot", value: model.listProfile == "*" ? "All bots" : (model.listProfile ?? rt.selectedProfile ?? "—"))
                        LabeledContent("Summaries", value: model.summaries.isEmpty ? "off on iPhone" : "\(model.summaries.count) from iPhone")
                    }
                    if model.store.connections.count > 1 {
                        // More than one saved gateway: the watch can move between them itself.
                        Section("Gateways") {
                            ForEach(model.store.connections) { c in
                                Button { Task { await model.activate(c); dismiss() } } label: {
                                    HStack {
                                        Text(c.name).lineLimit(1)
                                        Spacer()
                                        if c.id == rt.connection.id { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        Picker("Connect through", selection: Binding(get: { model.route }, set: { r in Task { await model.setRoute(r) } })) {
                            Text("Automatic").tag(GatewayRoute.automatic)
                            Text("iPhone only").tag(GatewayRoute.relayOnly)
                        }
                    } footer: {
                        Text(model.route == .relayOnly
                             ? "Everything goes through your iPhone, so it needs to be nearby. Use this when the watch's own Wi-Fi cannot reach the gateway."
                             : "The watch uses its own connection while the gateway answers there, and goes through your iPhone when it does not.")
                    }
                    Section {
                        if model.route != .relayOnly {
                            Button { Task { await rt.reconnectNow() } } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                        }
                    } footer: { Text("Sending and approving go through the iPhone unless the watch has a live connection of its own. Summaries and bot looks come from the iPhone.") }
                } else {
                    Section { Text("Open Vory on the iPhone once; it hands the gateway to the watch.").font(.footnote) }
                }
                Section {
                    LabeledContent("Version", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
