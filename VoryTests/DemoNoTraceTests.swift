import Foundation
import Testing
@testable import VoryCore
@testable import Vory

/// Demo mode leaves no trace on the device and sends nothing anywhere (#392). A demo used end to end through the real
/// client (every chat opened, a turn sent and its approval answered, a chat renamed, the board read, a picture fetched,
/// a file downloaded, an attachment staged) and then left has written none of the core's stores: no defaults of its
/// own, no transcript cache, no shared media cache, no widget snapshot, nothing left in its scratch folder, no saved
/// connection. And nothing it did asked the network: no request through the shared session (the push relay's and the
/// sign-in's) and none its own sessions had to refuse.
@MainActor
@Suite(.serialized) struct DemoNoTraceTests {
    /// Every request the shared session is asked for while the demo runs, recorded and failed.
    final class SharedSessionWatch: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var urls: [String] = []
        static var seen: [String] { lock.withLock { urls } }
        static func reset() { lock.withLock { urls = [] } }
        override class func canInit(with request: URLRequest) -> Bool {
            lock.withLock { urls.append(request.url?.absoluteString ?? "no URL") }
            return true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }

    private func waitUntil(_ seconds: Double = 15, _ done: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private static var sharedMedia: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("vory-media", isDirectory: true)
    }

    private static func files(in dir: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    }

    /// Each demo chat's transcript cache file, by path, with when it was last written (none: absent). A copy an older
    /// build left there (one without the guard) is not this run's: what counts is that nothing writes it now.
    private static func cacheStamps() -> [String: Date] {
        var out: [String: Date] = [:]
        for c in DemoContent.chats {
            guard let u = TranscriptCache.url(connection: GatewayConnection.demoID, storedID: c.id),
                  let d = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date else { continue }
            out[u.path] = d
        }
        return out
    }

    /// A runtime on the demo's transport keeps nothing whatever its connection: onboarding's tour (#388) makes one of its
    /// own for a moment, not on the demo connection, and every store's check (`isEphemeral`) covers it as it covers the
    /// demo. The same connection over the network is an ordinary gateway.
    @Test func aRuntimeOnTheDemoTransportIsEphemeralWhateverItsConnection() async throws {
        let store = ConnectionStore(defaults: UserDefaults(suiteName: "dev.vory.tests.demotrace." + UUID().uuidString)!, connections: [])
        let own = GatewayConnection(name: "tour", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        #expect(!own.isDemo)
        let tour = GatewayRuntime(connection: own, store: store, transport: .demo(DemoGateway(pace: .quick)))
        #expect(tour.isEphemeral)
        #expect(tour.scratchDirectory.path != FileManager.default.temporaryDirectory.path, "the tour's files would go to the shared folder")
        await tour.stop()
        let net = GatewayRuntime(connection: own, store: store)
        #expect(!net.isEphemeral)
        #expect(net.scratchDirectory.path == FileManager.default.temporaryDirectory.path)
    }

    @Test func aDemoUsedAndLeftLeavesNoTraceAndSendsNothingAnywhere() async throws {
        let cacheBefore = Self.cacheStamps()
        let defaultsBefore = UserDefaults.standard.dictionaryRepresentation()
        let renamedBefore = UserDefaults.standard.stringArray(forKey: ChatSession.renamedByPersonKey) ?? []
        let snapshotBefore = WidgetSnapshot.load()
        let mediaBefore = Self.files(in: Self.sharedMedia)
        let refusedBefore = DemoURLProtocol.refused
        SharedSessionWatch.reset()
        URLProtocol.registerClass(SharedSessionWatch.self)
        defer { URLProtocol.unregisterClass(SharedSessionWatch.self) }

        let suite = "dev.vory.tests.demotrace." + UUID().uuidString
        let store = ConnectionStore(defaults: UserDefaults(suiteName: suite)!, connections: [])
        store.activeConnectionID = GatewayConnection.demoID
        let rt = GatewayRuntime(connection: .demo, store: store, transport: .demo(DemoGateway(pace: .quick)))
        await rt.start()
        let scratch = rt.scratchDirectory
        #expect(scratch.path != FileManager.default.temporaryDirectory.path)

        // Every chat opened and read (each would have been cached on a real gateway).
        for c in DemoContent.chats {
            let chat = try await rt.openChat(storedID: c.id, title: c.title, profile: c.bot, waitForResume: true)
            #expect(!chat.items.isEmpty, "\(c.title) opened empty")
        }
        // A turn with its approval, then a rename.
        let chat = try await rt.newChat(profile: "default")
        _ = await chat.send("What's taking up the most space on my server?")
        await waitUntil { chat.cards.contains { $0.method == "approval" } }
        let card = try #require(chat.cards.first { $0.method == "approval" })
        await chat.respond(card: card, result: .object(["choice": .string("once")]))
        let done = try #require(DemoContent.cleanup.approval).done
        await waitUntil { !chat.isRunning && chat.items.contains { if case .assistant(let t, _, _) = $0.kind { return t.contains(done) }; return false } }
        await chat.rename("Server space")
        // The board (read, and a board chosen), a picture, a download, an attachment staged.
        await rt.kanban.refresh()
        rt.kanban.select(board: "default")
        let picture = try await rt.media.localURL(for: MediaRef(path: "/home/demo/images/ereader-battery.png"),
                                                  gateway: rt.connection.id.uuidString, api: GatewayMediaAPI(api: rt.api))
        #expect(picture.path.hasPrefix(scratch.path), "the picture went to \(picture.path)")
        let download = try await rt.api.download("/api/files/download", query: [URLQueryItem(name: "path", value: "/home/demo/trip/packing.md")])
        #expect(download.path.hasPrefix(scratch.path), "the download went to \(download.path)")
        chat.stageAttachment(data: Data("hello".utf8), name: "note.txt", kind: .file)
        #expect(chat.staged.first?.localURL?.path.hasPrefix(scratch.path) == true)
        await rt.stop()

        // No trace. The defaults: no key of the core's for the demo, and nothing that names its gateway or a chat of it.
        let demoIDs = [GatewayConnection.demoID.uuidString, chat.storedID] + DemoContent.chats.map(\.id)
        let added = UserDefaults.standard.dictionaryRepresentation().filter { defaultsBefore[$0.key] == nil }.map(\.key)
        let ours = added.filter { key in demoIDs.contains { key.contains($0) } || ["kanban.", "gateway.", "chat.", "chats.", "transcript"].contains { key.hasPrefix($0) } }
        #expect(ours.isEmpty, "the demo wrote defaults: \(ours.sorted())")
        let renamed = UserDefaults.standard.stringArray(forKey: ChatSession.renamedByPersonKey) ?? []
        #expect(renamed == renamedBefore, "the demo's rename was recorded")
        #expect(Self.cacheStamps() == cacheBefore, "a demo chat was written to the transcript cache")
        #expect(TranscriptCache.load(connection: GatewayConnection.demoID, storedID: chat.storedID) == nil, "the new chat was cached")
        #expect(Self.files(in: Self.sharedMedia) == mediaBefore, "the shared media cache changed")
        #expect(WidgetSnapshot.load() == snapshotBefore, "the widgets' snapshot changed")
        #expect(!FileManager.default.fileExists(atPath: scratch.path), "the demo's scratch folder is still there")
        #expect(store.connections.isEmpty && UserDefaults(suiteName: suite)?.string(forKey: "activeConnectionID") == nil)
        // Nothing sent anywhere.
        #expect(SharedSessionWatch.seen.isEmpty, "the shared session was asked for \(SharedSessionWatch.seen)")
        #expect(DemoURLProtocol.refused == refusedBefore, "a demo session asked for another host")
    }

    /// Home's "since you were here" mark is kept from the person's own visits only: a visit in the demo writes none, so
    /// after leaving it Home measures from their own last visit (the demo legs found the demo's Home visit kept).
    @Test func homesVisitMarkIsNeverTheDemos() {
        #expect(HomeVisit.mark(kept: 100, visitStart: 200, inDemo: true) == nil)
        #expect(HomeVisit.mark(kept: 0, visitStart: 200, inDemo: true) == nil)
        #expect(HomeVisit.mark(kept: 100, visitStart: 200, inDemo: false) == 200)
        #expect(HomeVisit.mark(kept: 300, visitStart: 200, inDemo: false) == 300)
    }
}
