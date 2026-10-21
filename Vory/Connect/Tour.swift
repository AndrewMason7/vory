#if os(iOS)
import SwiftUI
import UIKit
import VoryCore

/// The first-run tour (#388, the copy Matt approved on 2026-10-19): six beats, swiped or stepped through, with Vory, the
/// app icon's glass cloud, as one character on a layer above the pages. He floats while the page is still, flies to
/// his place on the next page as the finger moves it (a lag and a lean), and talks in his typed bubble. Each beat also
/// plays on its own. With Reduce Motion he doesn't float or fly: he is beside each page, and the change cross-fades.
/// Built from the app's own parts and styles (BotFaceView, the glass buttons, the app's fonts and colours), so the tour
/// shows the app as it is. Beats 3 and 4 are a real chat with Sprout on the tour's own demo (`TourChat`), never the
/// app's gateway in use; nothing here touches a gateway, and the demo bots' looks are never saved.
struct TourView: View {
    /// Restore from iCloud (beat 1). Not offered when nil (a replay: the gateways are here).
    var onRestore: (() -> Void)?
    /// Connect your gateway (beat 6): the gateway form.
    var onConnect: () -> Void
    /// Try a demo (beat 6), where Demo mode offers it.
    var onDemo: (() -> Void)?
    /// Straight to the last beat (a restore that brought no gateway).
    var startAtConnect = false
    /// A replay over the running app (#487, `TourReplayView`): Skip closes it rather than going to the last beat, and
    /// the last beat has Done.
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.windowGeometry) private var windowGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The person's text size, before the tour's cap: at the accessibility sizes Vory takes his compact places.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var compact: Bool { dynamicTypeSize.isAccessibilitySize }
    /// The tour on screen (not covered by the gateway form, the app in front): Vory's float and the bots' orbit run
    /// only then (the battery rule).
    @State private var onScreen = false
    @State private var page: TourBeat? = .hello
    /// The pages' scroll as a fraction of pages (2.5 is halfway from the third to the fourth): Vory's flight follows it.
    @State private var progress: CGFloat = 0
    /// What each beat's bubble says now: its first line, then the next as the beat moves on (`TourLines`).
    @State private var line = TourLines()
    /// The tour's own demo for beats 3 and 4, made as the tour comes up.
    @State private var tourChat: TourChat?
    /// Where the tour's chat has got to: Vory's lines follow it, and an approval card moves the tour on to beat 4.
    @State private var chatPhase: TourChatPhase = .ready
    @State private var moveOn: Task<Void, Never>?
    /// The card has been answered, once per chat: the cheer and the mention come once.
    @State private var answered = false
    /// Beat 4's mention is due (a moment after the answer): the message bar types it in.
    @State private var mentionDue = false
    @State private var mentionTimer: Task<Void, Never>?
    /// Where Vory's bubble ends and where Continue and the dots start, in the tour's space: the chat and the first and
    /// last beats keep between them, whatever the text size makes them.
    @State private var bubbleBottom: CGFloat = 0
    @State private var controlsTop: CGFloat = 0
    /// Beat 5's place on show: each in turn, until its line has been read (`TourPlace.dwell`).
    @State private var place: TourPlace = TourPlace.all(pad: DeviceWords.device == "iPad")[0]

    /// The tour's own words and buttons, and Vory's bubble, grow no larger than this (the planner's call, 2026-10-20):
    /// past it, Vory, his bubble, the pages and the buttons ran over each other. Its buttons show the Large Content
    /// Viewer; VoiceOver reads all of it whole; the app's chat inside it keeps every size.
    static let largestText: DynamicTypeSize = .accessibility2
    /// The tour's own space, where the bubble's end and the controls' start are measured.
    nonisolated static let space = "tour"

    private var current: TourBeat { page ?? .hello }
    private var places: [TourPlace] { TourPlace.all(pad: DeviceWords.device == "iPad") }
    /// A keyboard up over the tour's chat (the person tapped its message bar).
    private var typingInChat: Bool { current.showsChat && !windowGeometry.keyboard.isNull }
    private var animating: Bool { onScreen && scenePhase == .active && !reduceMotion }
    /// The tour's demo runs from the bots beat (so the chat is there as it slides in) through the approval beat, and
    /// while any of its chat is in view, with the tour on screen. It stops past them, and starts afresh on the way back.
    private var wantsChat: Bool {
        onScreen && (current == .bots || current.showsChat || abs(TourChatLayer.slide(progress)) < 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TourGlow(progress: progress)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(TourBeat.allCases) { beat in
                            beatPage(beat, size: geo.size)
                                .dynamicTypeSize(...Self.largestText)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(beat)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .scrollDisabled(reduceMotion)
                .onScrollGeometryChange(for: CGFloat.self) { g in g.contentOffset.x / max(1, g.containerSize.width) } action: { _, p in
                    progress = p
                }
                // Beats 3 and 4's chat, over their pages: it comes and goes with them.
                if let chat = tourChat?.chat {
                    // The app's own chat keeps every text size; its room comes from what's around it as measured.
                    TourChatLayer(chat: chat, progress: reduceMotion ? CGFloat(current.rawValue) : progress, size: geo.size,
                                  origin: geo.frame(in: .global).origin, mention: mentionDue,
                                  room: TourChatLayer.Room(top: bubbleBottom, bottom: controlsTop))
                        .id(ObjectIdentifier(chat))
                    TourChatWatch(chat: chat) { chatMoved(to: $0) }
                        .id(ObjectIdentifier(chat))
                }
                // Vory, over every page, in his place for the scroll.
                VoryTourLayer(progress: reduceMotion ? CGFloat(current.rawValue) : progress, size: geo.size,
                              says: line.text(for: current), lineKey: line.key(for: current), reduceMotion: reduceMotion,
                              animating: animating, lookingDown: current == .connect,
                              squint: current.showsChat && chatPhase == .working,
                              hop: current == .everywhere ? place.rawValue : 0, bubbleBottom: $bubbleBottom, compact: compact)
                    .dynamicTypeSize(...Self.largestText)
                    .allowsHitTesting(false)
                    // The person typing in the tour's chat: the chat takes the room, and Vory steps aside until they're done.
                    .opacity(typingInChat ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: typingInChat)
                controls
                    .dynamicTypeSize(...Self.largestText)
            }
            .coordinateSpace(.named(Self.space))
        }
        // The keyboard (beat 3's message bar) moves nothing but the chat, which rises over it.
        .ignoresSafeArea(.keyboard)
        .background(Color(.systemBackground))
        .onAppear {
            onScreen = true
            if startAtConnect { page = .connect }
            if tourChat == nil {
                tourChat = TourChat(appHasGateway: { [model] in model.hasConnections }, appInDemo: { [model] in model.isInDemo })
            }
        }
        .onDisappear {
            onScreen = false
            moveOn?.cancel()
            mentionTimer?.cancel()
            Task { [tourChat] in await tourChat?.stop() }
        }
        .onChange(of: wantsChat, initial: true) { _, wants in
            guard let tourChat else { return }
            Task { if wants { await tourChat.start() } else { await tourChat.stop() } }
        }
        .onChange(of: page) { _, beat in
            guard let beat else { return }
            line.arrived(at: beat)
            // Beat 5 starts from its first place each time it comes into view.
            if beat == .everywhere { showPlace(places[0]) }
            // Landing on Connect: Vory settles beside it, with a tap on the hand.
            if beat == .connect { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            // An answer given on beat 3 has its mention on arriving at beat 4.
            if beat == .approval { scheduleMention() }
        }
        .task(id: PlaceTimer(onBeat: onScreen && current == .everywhere, place: place)) {
            guard onScreen, current == .everywhere else { return }
            try? await Task.sleep(for: .seconds(place.dwell))
            guard !Task.isCancelled else { return }
            nextPlace()
        }
        .task(id: LineTimer(beat: current, asked: chatPhase == .asked)) {
            // Each beat's second line, a moment after its first has been read (beat 4's once its card is up).
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            line.advance(on: current, demo: onDemo != nil, asked: chatPhase == .asked)
        }
    }

    private struct LineTimer: Hashable { var beat: TourBeat; var asked: Bool }
    private struct PlaceTimer: Hashable { var onBeat: Bool; var place: TourPlace }

    /// Beat 5's next place, once this one has been read; the last stays.
    private func nextPlace() {
        guard let i = places.firstIndex(of: place), i + 1 < places.count else { return }
        showPlace(places[i + 1])
    }

    private func showPlace(_ p: TourPlace) {
        place = p
        line.placeShown(p)
        if UIAccessibility.isVoiceOverRunning { AccessibilityNotification.Announcement(p.spoken).post() }
    }

    /// The tour's chat moved on: Vory's lines follow, with a tap on the hand at Send and at an allowed card, and
    /// VoiceOver told what the screen alone shows. The card coming up moves the tour on to beat 4 once the line
    /// about the reply has been read; its answer (the first only) brings the cheer, then the mention.
    private func chatMoved(to phase: TourChatPhase) {
        let was = chatPhase
        guard phase != was else { return }
        chatPhase = phase
        line.chatMoved(to: phase)
        if phase == .ready {
            // A fresh chat (the tour back after its demo stopped): its answer and mention are still to come.
            answered = false
            mentionDue = false
            mentionTimer?.cancel()
        }
        if was == .ready, phase == .working { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if was == .working, phase == .replied || phase == .asked { AccessibilityNotification.Announcement("Sprout replied").post() }
        if phase == .asked, current == .chat {
            moveOn?.cancel()
            moveOn = Task {
                try? await Task.sleep(for: .seconds(2.6))
                guard !Task.isCancelled, current == .chat, chatPhase == .asked else { return }
                go(to: .approval)
            }
        }
        if case .answered(let allowed) = phase, !answered {
            answered = true
            if allowed {
                // Vory cheers: his finish spin, as a bot's at the end of a turn.
                BotAmbient.shared.turnFinished(profile: "vory-tour")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AccessibilityNotification.Announcement("Approved. Sprout cleared 3.1 gigabytes.").post()
            }
            scheduleMention()
        }
    }

    /// Beat 4's last moment, once the answer's line has been read: "Type @ to bring another bot in.", and the message
    /// bar types a mention of Gizmo (shown, not sent). Only on beat 4: an answer given on beat 3 has it on arrival.
    private func scheduleMention() {
        guard answered, !mentionDue, current == .approval else { return }
        mentionTimer?.cancel()
        mentionTimer = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled, current == .approval else { return }
            line.mentionCame()
            mentionDue = true
        }
    }

    // MARK: Pages

    @ViewBuilder private func beatPage(_ beat: TourBeat, size: CGSize) -> some View {
        switch beat {
        case .hello:
            TourHelloBeat(onStart: { go(to: .bots) }, onRestore: onRestore, below: bubbleBottom, above: controlsTop)
        case .bots:
            TourBotsBeat(centre: VoryTourLayer.anchor(for: .bots, in: size, compact: compact), live: current == .bots && animating, reduceMotion: reduceMotion) {
                line.botTapped()
            }
        case .chat, .approval:
            // The chat itself is on its own layer over these two pages (`TourChatLayer`).
            Color.clear
        case .everywhere:
            TourEverywhere(place: place, size: size, reduceMotion: reduceMotion, live: onScreen && current == .everywhere, below: bubbleBottom, above: controlsTop)
        case .connect:
            TourConnectBeat(onConnect: onConnect, onDemo: onDemo, below: bubbleBottom, above: controlsTop)
        }
    }

    private func go(to beat: TourBeat) {
        if reduceMotion { page = beat } else { withAnimation(.smooth(duration: 0.45)) { page = beat } }
    }

    // MARK: Controls

    /// Skip at the top on every beat but the last; Continue and the page dots along the bottom, where the beat itself
    /// has no button of its own.
    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if current != .connect {
                    Button("Skip") { if let onClose { onClose() } else { go(to: .connect) } }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.glass)
                        .accessibilityShowsLargeContentViewer()
                        .accessibilityLabel("Skip the tour")
                        .accessibilityIdentifier("onboarding.skip")
                } else if let onClose {
                    Button("Done", action: onClose)
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.glass)
                        .accessibilityShowsLargeContentViewer()
                        .accessibilityLabel("Done with the tour")
                        .accessibilityIdentifier("onboarding.done")
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            Spacer()
            VStack(spacing: 14) {
                if current != .hello && current != .connect {
                    Button {
                        go(to: TourBeat(rawValue: current.rawValue + 1) ?? .connect)
                    } label: {
                        Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityShowsLargeContentViewer()
                    .accessibilityIdentifier("onboarding.continue")
                    .frame(maxWidth: 380)
                }
                TourDots(page: current, count: TourBeat.allCases.count) { go(to: $0) }
            }
            .padding(.horizontal, 24).padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { controlsTop = $0 }
        }
    }
}

/// The six beats, in order.
enum TourBeat: Int, CaseIterable, Identifiable, Hashable {
    case hello, bots, chat, approval, everywhere, connect
    var id: Int { rawValue }
    /// The beats the tour's chat is on.
    var showsChat: Bool { self == .chat || self == .approval }
}

/// What Vory says on each beat, in the approved words: a first line on arrival, the next once it has been read (or a
/// bot has been tapped). Each line has a key of its own, so the bubble types it out once.
struct TourLines: Equatable {
    private var step: [TourBeat: Int] = [:]
    private var tapped = false
    /// The tour's chat had its card answered: beat 4's lines have moved past it for good.
    private var answered = false

    /// Vory's line after a Deny (Matt, 2026-10-20).
    static let afterDeny = "That\u{2019}s fine too. Nothing happens without your OK."

    static func lines(_ beat: TourBeat, demo: Bool) -> [String] {
        switch beat {
        case .hello: return ["Hi, I\u{2019}m Vory.", "I bring your Hermes agents to life as bots."]
        case .bots: return ["Every agent on your gateway shows up as a bot.", "Go on, tap one.", "They each get a face, a name and a title."]
        case .chat: return ["This is a chat with Sprout. Tap Send.", "Sprout\u{2019}s on it. You can watch it work.",
                            "That ring fills as the chat uses up its memory."]
        // In order: on arrival, once the card is up, after an allow, the mention, after a Deny.
        case .approval: return ["Sprout asks before it does anything risky.", "It\u{2019}s your call. Tap Allow once to let it go ahead.",
                                "Done. Sprout cleared 3.1 GB.", "Type @ to bring another bot in.", afterDeny]
        // By place (`placeShown`): the three places an ask reaches share the first.
        case .everywhere: return ["You\u{2019}ll see these wherever you are.", "I\u{2019}m on your \(TourPlace.otherDevice) and Mac too.",
                                  "Give me a backup address and I\u{2019}ll still find you away from home.",
                                  "Your gateways and bot looks sync through iCloud."]
        case .connect: return demo ? ["Let\u{2019}s connect your gateway.", "Or take me for a spin first."] : ["Let\u{2019}s connect your gateway."]
        }
    }

    func text(for beat: TourBeat) -> String {
        let all = Self.lines(beat, demo: true)
        return all[min(step[beat] ?? 0, all.count - 1)]
    }

    func key(for beat: TourBeat) -> String { "\(beat.rawValue)-\(step[beat] ?? 0)" }

    /// A beat comes into view: its first line, unless it has moved on already (back to a beat already seen).
    mutating func arrived(at beat: TourBeat) { if step[beat] == nil { step[beat] = 0 } }

    /// The beat's next line, a moment in; not past the lines it has, and the bots' last line only after a tap. Beat 3
    /// follows its chat instead (`chatMoved`); beat 4's second line waits for the card, and its last for the answer.
    mutating func advance(on beat: TourBeat, demo: Bool, asked: Bool = false) {
        let count = Self.lines(beat, demo: demo).count
        let now = step[beat] ?? 0
        if beat == .bots, now >= 1 { return }
        if beat == .chat || beat == .everywhere { return }
        if beat == .approval, now >= 1 || !asked { return }
        if now + 1 < count { step[beat] = now + 1 }
    }

    /// The tour's chat moved on: beat 3's lines follow it (Send, the work, the reply), and beat 4's answer line comes
    /// with the card's first answer (a later message's reply leaves beat 4 where it is). A fresh chat (back on beat 3
    /// after the demo stopped) starts both again.
    mutating func chatMoved(to phase: TourChatPhase) {
        switch phase {
        case .ready:
            step[.chat] = 0
            step[.approval] = nil
            answered = false
        case .working: step[.chat] = 1
        case .replied, .asked: step[.chat] = 2
        case .answered(let allowed):
            step[.chat] = 2
            guard !answered else { return }
            answered = true
            step[.approval] = allowed ? 2 : 4
        }
    }

    /// The mention, a moment after the answer: beat 4's last line.
    mutating func mentionCame() { step[.approval] = 3 }

    /// Beat 5's line for the place on show.
    mutating func placeShown(_ place: TourPlace) {
        switch place {
        case .island, .lockScreen, .watch: step[.everywhere] = 0
        case .devices: step[.everywhere] = 1
        case .homeAway: step[.everywhere] = 2
        case .iCloud: step[.everywhere] = 3
        }
    }

    mutating func botTapped() {
        guard !tapped else { return }
        tapped = true
        step[.bots] = 2
    }
}

// MARK: Vory

/// Vory on his layer: the glass cloud from the app icon (`BotLookSpec.vory`), where the scroll puts him between his
/// places on two pages, leaning into the move and lagging it a little; floating gently when the page is still. His
/// typed bubble goes with him. Reduce Motion: in his place on the page in front, no float, no lean.
struct VoryTourLayer: View {
    var progress: CGFloat
    var size: CGSize
    var says: String
    var lineKey: String
    var reduceMotion: Bool
    /// The float runs: the tour on screen, the app in front, no Reduce Motion.
    var animating = true
    var lookingDown = false
    /// The thinking squint, while Sprout works in the tour's chat.
    var squint = false
    /// A change hops him (beat 5's places, as he goes from one to the next).
    var hop = 0
    /// Where his bubble ends, in the tour's space.
    @Binding var bubbleBottom: CGFloat
    /// His smaller, higher places, for the accessibility text sizes (`place(_:compact:)`).
    var compact = false

    /// The bubble's frame: the most it can grow to, from its top.
    static let bubbleRoom: CGFloat = 420

    /// His place and size on each beat, as fractions of the screen and points; `bubbleTop`, a fraction of the height,
    /// where his bubble's top sits when it isn't just under him. On the bots beat it's above the orbit: under him, the
    /// bots circling him crossed it.
    struct Place { var x: CGFloat; var y: CGFloat; var size: CGFloat; var bubbleTop: CGFloat? = nil }
    /// `compact`: at the accessibility text sizes he's smaller and higher, so his bubble and the page's words and buttons
    /// fit under him on the smallest phone.
    static func place(_ beat: TourBeat, compact: Bool = false) -> Place {
        switch (beat, compact) {
        case (.hello, false): return Place(x: 0.5, y: 0.30, size: 150)
        case (.hello, true): return Place(x: 0.5, y: 0.13, size: 84)
        case (.bots, false): return Place(x: 0.5, y: 0.42, size: 92, bubbleTop: 0.12)
        case (.bots, true): return Place(x: 0.5, y: 0.50, size: 64, bubbleTop: 0.10)
        case (.chat, false), (.approval, false), (.everywhere, false): return Place(x: 0.5, y: 0.13, size: 64)
        case (.chat, true), (.approval, true), (.everywhere, true): return Place(x: 0.5, y: 0.08, size: 44)
        case (.connect, false): return Place(x: 0.5, y: 0.28, size: 112)
        case (.connect, true): return Place(x: 0.5, y: 0.12, size: 72)
        }
    }

    static func anchor(for beat: TourBeat, in size: CGSize, compact: Bool = false) -> CGPoint {
        let p = place(beat, compact: compact)
        return CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    /// His face's centre on a page, in points.
    static func faceY(_ p: Place, in size: CGSize) -> CGFloat { p.y * size.height + p.size * 0.46 - 22 }
    /// His bubble's top on a page, in points: just under his face (it tucks a little under his chin), or where the beat
    /// puts it.
    static func bubbleTop(_ p: Place, in size: CGSize) -> CGFloat { p.bubbleTop.map { $0 * size.height } ?? faceY(p, in: size) + p.size * 0.38 }

    /// Where he and his bubble are between two pages, for a fractional page: in points. `tail`, how much of the bubble's
    /// tail shows: all of it under him, none once it hangs 40 points or more from there (it pointed up at nothing).
    private var spot: (x: CGFloat, faceY: CGFloat, bubbleTop: CGFloat, size: CGFloat, tail: CGFloat) {
        let last = CGFloat(TourBeat.allCases.count - 1)
        let p = min(max(progress, 0), last)
        let i = Int(p.rounded(.down)), f = p - CGFloat(i)
        let a = Self.place(TourBeat(rawValue: i) ?? .hello, compact: compact), b = Self.place(TourBeat(rawValue: min(i + 1, Int(last))) ?? .connect, compact: compact)
        func mix(_ u: CGFloat, _ v: CGFloat) -> CGFloat { u + (v - u) * f }
        func under(_ p: Place) -> CGFloat { Self.faceY(p, in: size) + p.size * 0.38 }
        let top = mix(Self.bubbleTop(a, in: size), Self.bubbleTop(b, in: size))
        return (mix(a.x, b.x) * size.width, mix(Self.faceY(a, in: size), Self.faceY(b, in: size)), top, mix(a.size, b.size),
                max(0, 1 - abs(top - mix(under(a), under(b))) / 40))
    }

    /// The lean into a move: most in the middle of a page change, none at rest.
    private var lean: Double {
        let f = progress - progress.rounded(.down)
        return reduceMotion ? 0 : Double(sin(f * .pi)) * 9
    }

    var body: some View {
        let s = spot
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bob = reduceMotion ? 0 : sin(t * 1.3) * 5
            let sway = reduceMotion ? 0 : sin(t * 0.8) * 2
            ZStack {
                BotFaceView(spec: BotLookSpec.vory, size: s.size, active: true,
                            gaze: lookingDown ? CGPoint(x: 0, y: 0.6) : .zero,
                            mood: BotFaceView.Mood(profile: "vory-tour", state: .guide, squint: squint))
                    .rotationEffect(.degrees(lean + sway))
                    .offset(y: bob)
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: hop) { face, y in
                        face.offset(y: reduceMotion ? 0 : y)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(-18, duration: 0.18)
                            SpringKeyframe(0, duration: 0.42, spring: .bouncy)
                        }
                    }
                    .accessibilityLabel("Vory")
                    .position(x: s.x, y: s.faceY)
                // Hung from its top, so a second line grows down, as it did under him.
                // Hung from its top in a frame tall enough for the largest text the tour allows, so a longer line grows
                // down rather than being cut; its end is measured for what sits under it.
                VoryTypedBubble(text: says, key: lineKey, reduceMotion: reduceMotion, tail: s.tail)
                    .padding(.horizontal, 24)
                    .accessibilityLabel(says)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(TourView.space)).maxY } action: { bubbleBottom = $0 }
                    .frame(width: size.width, height: Self.bubbleRoom, alignment: .top)
                    .position(x: s.x, y: s.bubbleTop + Self.bubbleRoom / 2)
            }
            .frame(width: size.width, height: size.height)
        }
        // The lag behind the finger: his place eases after the scroll rather than sticking to it.
        .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 120, damping: 16), value: progress)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Beats

/// 1. Hello: Vory out of the launch screen into the glow, the line under him, and the two ways in.
private struct TourHelloBeat: View {
    var onStart: () -> Void
    var onRestore: (() -> Void)?
    /// Vory's bubble ends here and the tour's controls start there: the page's words and buttons stay between.
    var below: CGFloat = 0
    var above: CGFloat = 0

    var body: some View {
        TourColumn(top: below, bottom: above) {
            Text("Your Hermes agents, on \(DeviceWords.your).")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 14) {
                    Button(action: onStart) {
                        Text("Get Started").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityShowsLargeContentViewer()
                    .accessibilityHint("Starts a short tour.")
                    .accessibilityIdentifier("onboarding.getStarted")
                    if let onRestore {
                        Button(action: onRestore) {
                            Label("Restore from iCloud", systemImage: "icloud.and.arrow.down").font(.headline)
                                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                        .accessibilityShowsLargeContentViewer()
                        .accessibilityHint("Brings back the gateways you saved on another device.")
                        .accessibilityIdentifier("onboarding.restore")
                    }
                }
            }
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 28)
    }
}

/// 2. Your bots: the demo's five bots, each a different body, circling Vory. A tap plays the bot's own tap reaction
/// (the app's), with a tap on the hand, and its name and job come up under it.
private struct TourBotsBeat: View {
    var centre: CGPoint
    var live: Bool
    var reduceMotion: Bool
    var onTap: () -> Void
    @State private var picked: String?

    var body: some View {
        let bots = DemoBots.all
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !live)) { context in
            let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.18
            ZStack {
                ForEach(Array(bots.enumerated()), id: \.element.name) { i, bot in
                    let angle = turn + Double(i) / Double(bots.count) * 2 * .pi - .pi / 2
                    face(bot)
                        .position(x: centre.x + cos(angle) * 128, y: centre.y + 40 + sin(angle) * 118)
                }
            }
        }
    }

    private func face(_ bot: DemoBot) -> some View {
        Button {
            BotAmbient.shared.tap(profile: "tour-\(bot.name)")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .snappy) { picked = bot.name }
            onTap()
            AccessibilityNotification.Announcement("\(bot.display) says hi").post()
        } label: {
            VStack(spacing: 2) {
                BotFaceView(spec: BotLookSpec(shape: bot.shape, eyes: bot.eyes, hex: bot.hex), size: 58, active: true,
                            mood: BotFaceView.Mood(profile: "tour-\(bot.name)"))
                if picked == bot.name {
                    VStack(spacing: 0) {
                        Text(bot.display).font(.subheadline.weight(.semibold))
                        Text(bot.title).font(.caption).foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bot.display), \(bot.title)")
        .accessibilityHint("Double tap to say hi")
    }
}

/// 3 and 4. The tour's chat with Sprout, on the app's own chat parts (`TourChatCard`). One chat for both beats: it
/// comes in with beat 3, stays put while Vory moves on to beat 4, and goes with beat 4. With the keyboard up it rises
/// over it.
struct TourChatLayer: View {
    let chat: ChatSession
    var progress: CGFloat
    var size: CGSize
    /// The layer's top left in window space, where the window reports the keyboard.
    var origin: CGPoint
    /// Beat 4's mention is due: the message bar types it in.
    var mention = false
    /// What's around the chat, as measured: the chat sits between them.
    var room = Room()
    @Environment(\.windowGeometry) private var windowGeometry

    /// Where Vory's bubble ends (the chat starts under it) and where Continue and the dots start (the chat ends over
    /// them), in the tour's space; 0 when not yet measured.
    struct Room: Equatable { var top: CGFloat = 0; var bottom: CGFloat = 0 }

    /// Where the chat is across the pages, in widths from its place: in from the right with beat 3, still through
    /// beat 4, out to the left after it. In view while under one width.
    static func slide(_ progress: CGFloat) -> CGFloat {
        let first = CGFloat(TourBeat.chat.rawValue), last = CGFloat(TourBeat.approval.rawValue)
        if progress < first { return first - progress }
        if progress > last { return last - progress }
        return 0
    }

    var body: some View {
        let slide = Self.slide(progress)
        let frame = Self.frame(in: size, keyboardTop: keyboardTop, room: room)
        if abs(slide) < 1 {
            // Its own view, so the swipe moving it doesn't redraw the thread.
            TourChatCard(chat: chat, mention: mention)
                .frame(width: min(size.width - 32, 560), height: frame.height)
                .position(x: size.width / 2 + slide * size.width, y: frame.midY)
                .animation(.snappy, value: frame)
        }
    }

    /// The keyboard's top edge in the layer's space, when one is up (the person typing in the chat).
    private var keyboardTop: CGFloat? {
        let keyboard = windowGeometry.keyboard
        return keyboard.isNull ? nil : keyboard.minY - origin.y
    }

    /// Where the chat sits, top to bottom: under Vory and his bubble and over Continue and the dots, as measured, so at
    /// any text size Continue never covers its Send; with the keyboard up, from under Skip to just over the keyboard, Vory
    /// stepping aside meanwhile (`TourView`). Lifted whole, it went up over Vory and his bubble.
    static func frame(in size: CGSize, keyboardTop: CGFloat?, room: Room = Room()) -> CGRect {
        if let keyboardTop {
            let top: CGFloat = 60
            return CGRect(x: 0, y: top, width: size.width, height: max(160, keyboardTop - 8 - top))
        }
        let top = max(size.height * 0.30, room.top > 0 ? room.top + 10 : 0)
        let bottom = room.bottom > 0 ? room.bottom - 12 : size.height - 112
        return CGRect(x: 0, y: top, width: size.width, height: max(160, bottom - top))
    }
}

/// The tour's chat itself: the chat's header (Sprout seated on its pill, without the … menu), the thread, and the
/// message bar holding the ready-made message, which turns into the approval card when Sprout asks, and after the
/// answer types beat 4's mention. Its one framing of its own is the app's background in a rounded frame.
private struct TourChatCard: View {
    let chat: ChatSession
    var mention = false
    @State private var text = TourChat.readyMessage
    @State private var quote = ""
    @State private var dockTop: CGFloat = 0
    @State private var dockHeight: CGFloat = 60
    @Namespace private var dockSpace
    private static let topFade: CGFloat = 12

    var body: some View {
        // The header above the thread, not over it: in this small frame the thread ran under the pill with nothing behind
        // it (the app's chat has the bar's glass there), and its words read as overlapping. Nothing sits under the pill.
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ChatHeader(chat: chat, showBack: false, showsActions: false,
                           onBack: {}, onProfile: {}, onRename: {}, onContext: {}, onNewChat: {}, onClose: {})
                    .padding(.top, 10).padding(.bottom, 4)
                TranscriptView(chat: chat, dockTop: dockTop, fallbackInset: dockHeight, topInset: 0,
                               keyboardFloors: false, bandFade: Self.topFade)
                    // The thread fades out under the header rather than cut through a line; at rest its first row starts
                    // below the fade.
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.topFade)
                            Rectangle()
                        }
                    }
            }
            BottomDock(chat: chat, text: $text, quote: $quote, namespace: dockSpace)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { dockHeight = $0 } }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { dockTop = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onboarding.chatDock")
        }
        // The message bar stays at the card's foot at any text size: where the card's content is taller than its room
        // (the largest text on a small phone), it runs off the top, under the header, and Send and the card's answers
        // stay in view; centred, it ran off both ends, under Continue.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
        .clipped()
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: 32))
        .overlay { RoundedRectangle(cornerRadius: 32).strokeBorder(Color.primary.opacity(0.1)) }
        // The tour's Send is a step of it: no keyboard after it, which covered the chat and lifted it over Vory.
        .environment(\.composerFocusesAfterSend, false)
        .task(id: mention) {
            guard mention, text.isEmpty, let bot = TourChat.mentionBot else { return }
            await typeMention(bot)
        }
    }

    /// The mention as a person would make it, shown and not sent: "@Gi" typed, the message bar's own list coming up
    /// with Gizmo, then Gizmo picked from it (the app writes a bot's folder name, "@gizmo") and the rest of the draft.
    /// Anything typed meanwhile stops it.
    private func typeMention(_ bot: DemoBot) async {
        let query = "@" + String(bot.display.prefix(2))
        var shown = ""
        for c in query {
            guard text == shown else { return }
            shown.append(c)
            text = shown
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
        }
        try? await Task.sleep(for: .seconds(1.4))
        guard !Task.isCancelled, text == shown else { return }
        text = "@\(bot.name) " + TourChat.mentionDraft
    }
}

/// Follows the tour's chat for the tour (`TourChatPhase`) and draws nothing. The chat changes with every streamed
/// word and only this small view reads it, so the tour itself redraws only when the phase moves.
private struct TourChatWatch: View {
    let chat: ChatSession
    var moved: (TourChatPhase) -> Void
    @State private var tracker = TourChatTracker()

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: TourChatReading(chat), initial: true) { _, reading in moved(tracker.phase(for: reading)) }
            .accessibilityHidden(true)
    }
}

/// 6. Connect: Vory beside Connect your gateway; Try a demo where Demo mode offers it; the setup page for anyone new
/// to Hermes.
private struct TourConnectBeat: View {
    var onConnect: () -> Void
    var onDemo: (() -> Void)?
    /// Vory's bubble ends here and the tour's controls start there: the page's words and buttons stay between.
    var below: CGFloat = 0
    var above: CGFloat = 0

    var body: some View {
        TourColumn(top: below, bottom: above) {
            Text("You\u{2019}ll need a Hermes gateway running on a computer you own.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 14) {
                    Button(action: onConnect) {
                        Text("Connect your gateway").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityShowsLargeContentViewer()
                    .accessibilityHint("Opens the form for your gateway\u{2019}s address.")
                    .accessibilityIdentifier("onboarding.addGateway")
                    if let onDemo {
                        Button(action: onDemo) {
                            Text("Try a demo").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                        .accessibilityShowsLargeContentViewer()
                        .accessibilityHint("Opens Vory with demo bots, no gateway needed.")
                        .accessibilityIdentifier("onboarding.tryDemo")
                        Text("Demo bots stay on this device and go away when you connect.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 380)
            Link("New to Hermes? Start here.", destination: URL(string: "https://vory.dev/setup")!)
                .font(.subheadline)
                // A finger's height to hit: the line alone was 18 points.
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityLabel("New to Hermes? Start here. Opens the setup guide in Safari.")
                .accessibilityIdentifier("onboarding.setupHelp")
        }
        .padding(.horizontal, 28)
    }
}

// MARK: Pieces

/// A page's own words and buttons, at the foot of the room between Vory's bubble and the tour's controls (the dots), in
/// the tour's space; where they need more than that room (the largest text on a small phone) they scroll in it rather
/// than run under either.
private struct TourColumn<Content: View>: View {
    var top: CGFloat
    var bottom: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            // The scroll's edges sit a little outside the room, so the glass buttons' rims and shadows aren't cut; a
            // row scrolled up under the top fades out.
            let edge: CGFloat = 10
            let from = top + 12 - edge, to = (bottom > 0 ? bottom - 12 : geo.size.height - 64) + edge
            let room = max(0, to - from)
            ScrollView(.vertical) {
                VStack(spacing: 14) { content }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, edge)
                    .frame(minHeight: room, alignment: .bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: edge)
                    Rectangle()
                }
            }
            .frame(width: geo.size.width, height: room)
            .position(x: geo.size.width / 2, y: from + room / 2)
        }
    }
}

/// The page dots: where you are, a tap on one to go there; one element for VoiceOver, swiped up or down to move.
private struct TourDots: View {
    var page: TourBeat
    var count: Int
    var go: (TourBeat) -> Void

    var body: some View {
        // Each dot in a slot a finger can take, the gap between dots inside the slots, so they stand where they did; the
        // dots alone were 7 points, and the row too short for the audit's hit region.
        HStack(spacing: 0) {
            ForEach(TourBeat.allCases) { beat in
                Circle().fill(Color.primary.opacity(beat == page ? 0.85 : 0.22)).frame(width: 7, height: 7)
                    .frame(width: 15, height: 28)
                    .contentShape(.rect)
                    .onTapGesture { go(beat) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(page.rawValue + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if let next = TourBeat(rawValue: page.rawValue + 1) { go(next) }
            case .decrement: if let back = TourBeat(rawValue: page.rawValue - 1) { go(back) }
            @unknown default: break
            }
        }
    }
}

/// The soft glow behind the tour, in the demo bots' colours, drifting a little with the pages.
private struct TourGlow: View {
    var progress: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colours = DemoBots.all.compactMap { Color(botHex: $0.hex) }
        GeometryReader { geo in
            ZStack {
                ForEach(Array(colours.enumerated()), id: \.offset) { i, c in
                    let a = Double(i) / Double(max(colours.count, 1)) * 2 * .pi + Double(progress) * 0.6
                    Circle()
                        .fill(c.opacity(colorScheme == .dark ? 0.22 : 0.16))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 80)
                        .position(x: geo.size.width * (0.5 + 0.35 * cos(a)), y: geo.size.height * (0.38 + 0.22 * sin(a)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
