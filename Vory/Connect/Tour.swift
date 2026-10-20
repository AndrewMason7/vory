#if os(iOS)
import SwiftUI
import UIKit
import VoryCore

/// The first-run tour (#388, the copy Matt approved on 2026-10-19): six beats, swiped or stepped through, with Vory, the
/// app icon's glass cloud, as one character on a layer above the pages. He floats while the page is still, flies to
/// his place on the next page as the finger moves it (a lag and a lean), and talks in his typed bubble. Each beat also
/// plays on its own. With Reduce Motion he doesn't float or fly: he is beside each page, and the change cross-fades.
/// Built from the app's own parts and styles (BotFaceView, the glass buttons, the app's fonts and colours), so the tour
/// shows the app as it is. Nothing here touches a gateway; the demo bots' looks are never saved.
struct TourView: View {
    /// Restore from iCloud (beat 1).
    var onRestore: () -> Void
    /// Connect your gateway (beat 6): the gateway form.
    var onConnect: () -> Void
    /// Try a demo (beat 6), where Demo mode offers it.
    var onDemo: (() -> Void)?
    /// Straight to the last beat (a restore that brought no gateway).
    var startAtConnect = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The tour on screen (not covered by the gateway form, the app in front): Vory's float and the bots' orbit run
    /// only then (the battery rule).
    @State private var onScreen = false
    @State private var page: TourBeat? = .hello
    /// The pages' scroll as a fraction of pages (2.5 is halfway from the third to the fourth): Vory's flight follows it.
    @State private var progress: CGFloat = 0
    /// What each beat's bubble says now: its first line, then the next as the beat moves on (`TourLines`).
    @State private var line = TourLines()

    private var current: TourBeat { page ?? .hello }
    private var animating: Bool { onScreen && scenePhase == .active && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TourGlow(progress: progress)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(TourBeat.allCases) { beat in
                            beatPage(beat, size: geo.size)
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
                // Vory, over every page, in his place for the scroll.
                VoryTourLayer(progress: reduceMotion ? CGFloat(current.rawValue) : progress, size: geo.size,
                              says: line.text(for: current), lineKey: line.key(for: current), reduceMotion: reduceMotion,
                              animating: animating, lookingDown: current == .connect)
                    .allowsHitTesting(false)
                controls
            }
        }
        .background(Color(.systemBackground))
        .onAppear { onScreen = true; if startAtConnect { page = .connect } }
        .onDisappear { onScreen = false }
        .onChange(of: page) { _, beat in
            guard let beat else { return }
            line.arrived(at: beat)
            // Landing on Connect: Vory settles beside it, with a tap on the hand.
            if beat == .connect { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        .task(id: current) {
            // Each beat's second line, a moment after its first has been read.
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            line.advance(on: current, demo: onDemo != nil)
        }
    }

    // MARK: Pages

    @ViewBuilder private func beatPage(_ beat: TourBeat, size: CGSize) -> some View {
        switch beat {
        case .hello:
            TourHelloBeat(onStart: { go(to: .bots) }, onRestore: onRestore)
        case .bots:
            TourBotsBeat(centre: VoryTourLayer.anchor(for: .bots, in: size), live: current == .bots && animating, reduceMotion: reduceMotion) {
                line.botTapped()
            }
        case .chat, .approval, .everywhere:
            // Beats 3 to 5 are built from the app's own chat, approval card and frames (the next commits).
            Color.clear
        case .connect:
            TourConnectBeat(onConnect: onConnect, onDemo: onDemo)
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
                    Button("Skip") { go(to: .connect) }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.glass)
                        .accessibilityLabel("Skip the tour")
                        .accessibilityIdentifier("onboarding.skip")
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
                    .accessibilityIdentifier("onboarding.continue")
                    .frame(maxWidth: 380)
                }
                TourDots(page: current, count: TourBeat.allCases.count) { go(to: $0) }
            }
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
    }
}

/// The six beats, in order.
enum TourBeat: Int, CaseIterable, Identifiable, Hashable {
    case hello, bots, chat, approval, everywhere, connect
    var id: Int { rawValue }
}

/// What Vory says on each beat, in the approved words: a first line on arrival, the next once it has been read (or a
/// bot has been tapped). Each line has a key of its own, so the bubble types it out once.
struct TourLines: Equatable {
    private var step: [TourBeat: Int] = [:]
    private var tapped = false

    static func lines(_ beat: TourBeat, demo: Bool) -> [String] {
        switch beat {
        case .hello: return ["Hi, I\u{2019}m Vory.", "I bring your Hermes agents to life as bots."]
        case .bots: return ["Every agent on your gateway shows up as a bot.", "Go on, tap one.", "They each get a face, a name and a title."]
        case .chat: return ["This is a chat with Sprout. Tap Send."]
        case .approval: return ["Sprout asks before it does anything risky.", "It\u{2019}s your call. Tap Allow once to let it go ahead."]
        case .everywhere: return ["I\u{2019}m on your iPad too, with room for two columns."]
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

    /// The beat's next line, a moment in; not past the lines it has, and the bots' last line only after a tap.
    mutating func advance(on beat: TourBeat, demo: Bool) {
        let count = Self.lines(beat, demo: demo).count
        let now = step[beat] ?? 0
        if beat == .bots, now >= 1 { return }
        if now + 1 < count { step[beat] = now + 1 }
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

    /// His place and size on each beat, as fractions of the screen and points.
    struct Place { var x: CGFloat; var y: CGFloat; var size: CGFloat }
    static func place(_ beat: TourBeat) -> Place {
        switch beat {
        case .hello: return Place(x: 0.5, y: 0.30, size: 150)
        case .bots: return Place(x: 0.5, y: 0.42, size: 92)
        case .chat, .approval, .everywhere: return Place(x: 0.5, y: 0.13, size: 64)
        case .connect: return Place(x: 0.5, y: 0.28, size: 112)
        }
    }

    static func anchor(for beat: TourBeat, in size: CGSize) -> CGPoint {
        let p = place(beat)
        return CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    /// The place between two pages for a fractional page.
    private var spot: Place {
        let last = CGFloat(TourBeat.allCases.count - 1)
        let p = min(max(progress, 0), last)
        let i = Int(p.rounded(.down)), f = p - CGFloat(i)
        let a = Self.place(TourBeat(rawValue: i) ?? .hello), b = Self.place(TourBeat(rawValue: min(i + 1, Int(last))) ?? .connect)
        return Place(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, size: a.size + (b.size - a.size) * f)
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
            VStack(spacing: -s.size * 0.12) {
                BotFaceView(spec: BotLookSpec.vory, size: s.size, active: true,
                            gaze: lookingDown ? CGPoint(x: 0, y: 0.6) : .zero,
                            mood: BotFaceView.Mood(profile: "vory-tour", state: .guide))
                    .rotationEffect(.degrees(lean + sway))
                    .offset(y: bob)
                    .accessibilityLabel("Vory")
                VoryTypedBubble(text: says, key: lineKey, reduceMotion: reduceMotion)
                    .padding(.horizontal, 24)
                    .accessibilityLabel(says)
            }
            .frame(width: size.width)
            .position(x: s.x * size.width, y: s.y * size.height + s.size * 0.4)
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
    var onRestore: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Your Hermes agents, on \(DeviceWords.your).")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 14) {
                    Button(action: onStart) {
                        Text("Get Started").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityHint("Starts a short tour.")
                    .accessibilityIdentifier("onboarding.getStarted")
                    Button(action: onRestore) {
                        Label("Restore from iCloud", systemImage: "icloud.and.arrow.down").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .accessibilityHint("Brings back the gateways you saved on another device.")
                    .accessibilityIdentifier("onboarding.restore")
                }
            }
            .frame(maxWidth: 380)
            Spacer().frame(height: 64)
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

/// 6. Connect: Vory beside Connect your gateway; Try a demo where Demo mode offers it; the setup page for anyone new
/// to Hermes.
private struct TourConnectBeat: View {
    var onConnect: () -> Void
    var onDemo: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("You\u{2019}ll need a Hermes gateway running on a computer you own.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 14) {
                    Button(action: onConnect) {
                        Text("Connect your gateway").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityHint("Opens the form for your gateway\u{2019}s address.")
                    .accessibilityIdentifier("onboarding.addGateway")
                    if let onDemo {
                        Button(action: onDemo) {
                            Text("Try a demo").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                        .accessibilityHint("Opens Vory with demo bots, no gateway needed.")
                        .accessibilityIdentifier("onboarding.tryDemo")
                        Text("Demo bots stay on this device and go away when you connect.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: 380)
            Link("New to Hermes? Start here.", destination: URL(string: "https://vory.dev/setup")!)
                .font(.subheadline)
                .accessibilityLabel("New to Hermes? Start here. Opens the setup guide in Safari.")
                .accessibilityIdentifier("onboarding.setupHelp")
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: Pieces

/// The page dots: where you are, a tap on one to go there; one element for VoiceOver, swiped up or down to move.
private struct TourDots: View {
    var page: TourBeat
    var count: Int
    var go: (TourBeat) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TourBeat.allCases) { beat in
                Circle().fill(Color.primary.opacity(beat == page ? 0.85 : 0.22)).frame(width: 7, height: 7)
                    .onTapGesture { go(beat) }
            }
        }
        .padding(.vertical, 6)
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
