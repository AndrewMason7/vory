import Foundation
import Testing
@testable import Vory
import VoryCore

/// #283: a gateway's backup address. Which address is chosen and when, what the probe sends
/// (nothing that signs in), what counts as this gateway answering, and how the backup is
/// stored and synced without a 1.5 (20) device dropping it.
@MainActor
@Suite(.serialized) struct BackupAddressTests {
    private let home = try! GatewayURL.normalize("http://192.168.1.10:9119")
    private let away = try! GatewayURL.normalize("https://hermes.tail1234.ts.net")
    private let ours = GatewayIdentity(hermesHome: "/home/hermes/.hermes", configPath: "/home/hermes/.hermes/config.yaml", authRequired: false, authFlows: [], authProviders: [])

    /// A probe that answers each address after its delay with its identity (nil: no good answer).
    private func probe(_ answers: [GatewayURL: (ms: Int, identity: GatewayIdentity?)]) -> AddressChooser.Probe {
        { address in
            guard let a = answers[address] else { return nil }
            try? await Task.sleep(for: .milliseconds(a.ms))
            return a.identity
        }
    }

    private func timed(_ work: () async -> AddressChooser.Choice?) async -> (AddressChooser.Choice?, Double) {
        let start = ContinuousClock.now
        let c = await work()
        let d = ContinuousClock.now - start
        return (c, Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }

    @Test func theAddressThatWorkedLastWinsWithinItsHeadStart() async {
        let p = probe([home: (150, ours), away: (20, ours)])
        let c = await AddressChooser.choose(addresses: [home, away], lastGood: 0, known: ours, probe: p)
        #expect(c?.index == 0, "home answered within its head start")
    }

    @Test func anotherGoodAnswerWinsOnceTheHeadStartIsOver() async {
        let p = probe([home: (1500, ours), away: (20, ours)])
        let (c, seconds) = await timed { await AddressChooser.choose(addresses: [home, away], lastGood: 0, known: ours, probe: p) }
        #expect(c?.index == 1)
        #expect(seconds < 0.8, "chosen at the end of the head start, not after the slow address: \(seconds) s")
    }

    @Test func aPreferredAddressThatFailsDoesNotHoldTheChoice() async {
        let p = probe([home: (10, nil), away: (60, ours)])
        let (c, seconds) = await timed { await AddressChooser.choose(addresses: [home, away], lastGood: 0, known: ours, probe: p) }
        #expect(c?.index == 1)
        #expect(seconds < 0.25, "no waiting out a head start the failed address cannot use: \(seconds) s")
    }

    @Test func noGoodAnswerChoosesNothing() async {
        let p = probe([home: (10, nil), away: (20, nil)])
        #expect(await AddressChooser.choose(addresses: [home, away], lastGood: 1, known: ours, probe: p) == nil)
    }

    @Test func anAnswerFromAnotherGatewayIsPassedOver() async {
        var stranger = ours
        stranger.hermesHome = "/Users/someone/.hermes"
        let p = probe([home: (10, stranger), away: (400, ours)])
        let c = await AddressChooser.choose(addresses: [home, away], lastGood: 0, known: ours, probe: p)
        #expect(c?.index == 1, "the home address answered as another gateway: not this one")
    }

    @Test func whatCountsAsTheSameGateway() {
        #expect(ours.matches(nil), "nothing known yet")
        #expect(ours.matches(ours))
        var reordered = ours; reordered.authFlows = ["password", "device"]
        var known = ours; known.authFlows = ["device", "password"]
        #expect(reordered.matches(known), "the lists as sets")
        var gated = ours; gated.authRequired = true
        #expect(!gated.matches(ours))
        // A gated gateway names no paths: what both say must still agree.
        let closed = GatewayIdentity(authRequired: true, authFlows: ["password"], authProviders: ["basic"])
        #expect(closed.matches(GatewayIdentity(hermesHome: "/h", authRequired: true, authFlows: ["password"], authProviders: ["basic"])))
        #expect(!closed.matches(GatewayIdentity(authRequired: true, authFlows: ["device"], authProviders: ["basic"])))
    }

    @Test func theLabelsForAnAddress() throws {
        #expect(AddressChooser.label(for: home) == "Home network")
        #expect(AddressChooser.label(for: away) == "Tailscale")
        #expect(AddressChooser.label(for: try GatewayURL.normalize("https://hermes.example.com")) == "hermes.example.com")
        #expect(AddressChooser.label(for: try GatewayURL.normalize("http://100.101.102.103:9119")) == "Tailscale")
    }

    // MARK: The probe itself

    /// Answers every request from `handler`, and keeps what was asked.
    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: (URLRequest) -> (Int, [String: String], Data) = { _ in (404, [:], Data()) }
        nonisolated(unsafe) static var seen: [URLRequest] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.seen.append(request)
            let (status, headers, body) = Self.handler(request)
            let r = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            if (300..<400).contains(status), let to = headers["Location"].flatMap(URL.init(string:)) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: to), redirectResponse: r)
                return
            }
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private var stubbed: URLSessionConfiguration {
        let c = AddressChooser.probeConfiguration()
        c.protocolClasses = [StubProtocol.self]
        return c
    }
    nonisolated static let hermesStatus = Data(#"{"version":"0.21.4","gateway_running":true,"gateway_state":"running","active_sessions":1,"auth_required":false,"auth_providers":[],"auth_flows":[],"hermes_home":"/home/hermes/.hermes","config_path":"/home/hermes/.hermes/config.yaml"}"#.utf8)

    @Test func theProbeCarriesNoCredentials() async throws {
        StubProtocol.seen = []
        StubProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Self.hermesStatus) }
        let access = ["CF-Access-Client-Id": "id", "CF-Access-Client-Secret": "secret"]
        let probe = AddressChooser.statusProbe(accessHeaders: access, configuration: stubbed)
        #expect(await probe(home) == ours)
        let toHome = try #require(StubProtocol.seen.last)
        #expect(toHome.url?.path == "/api/status")
        for h in ["Authorization", "Cookie", "CF-Access-Client-Id", "CF-Access-Client-Secret", "X-Hermes-Session-Token"] {
            #expect(toHome.value(forHTTPHeaderField: h) == nil, "\(h) went to a home address")
        }
        // A public https host: its name vouched for by TLS, so Access may pass; still no sign-in.
        let tunnel = try GatewayURL.normalize("https://hermes.example.com")
        _ = await probe(tunnel)
        let toTunnel = try #require(StubProtocol.seen.last)
        #expect(toTunnel.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
        #expect(toTunnel.value(forHTTPHeaderField: "Authorization") == nil && toTunnel.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func onlyHermesStatusCountsAsAnAnswer() async throws {
        let probe = AddressChooser.statusProbe(accessHeaders: [:], configuration: stubbed)
        StubProtocol.handler = { _ in (200, ["Content-Type": "text/html"], Data("<html>router login</html>".utf8)) }
        #expect(await probe(home) == nil, "a router's page")
        StubProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data(#"{"ok":true}"#.utf8)) }
        #expect(await probe(home) == nil, "JSON, but not Hermes's status")
        StubProtocol.handler = { _ in (401, ["Content-Type": "application/json"], Self.hermesStatus) }
        #expect(await probe(home) == nil, "not a 200")
        StubProtocol.handler = { r in r.url?.path == "/api/status" ? (302, ["Location": "http://192.168.1.10:9119/portal"], Data()) : (200, [:], Self.hermesStatus) }
        #expect(await probe(home) == nil, "a redirect is never followed")
    }

    // MARK: Stored and synced

    @Test func aGatewaySavedBefore21StillDecodes() throws {
        let stored = Data(#"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Home","gateway":{"base":"http://192.168.1.10:9119"},"authMode":"sessionToken","createdAt":0,"hasAccessHeaders":false}]"#.utf8)
        let list = try JSONDecoder().decode([GatewayConnection].self, from: stored)
        #expect(list.count == 1 && list[0].alternate == nil && list[0].addresses == [home])
    }

    @Test func theSameGatewayAtItsBackupAddress() {
        var c = GatewayConnection(name: "Home", gateway: home, authMode: .sessionToken)
        #expect(c.using(away) == c, "not one of its addresses: unchanged")
        c.alternate = away
        let there = c.using(away)
        #expect(there.gateway == away && there.alternate == home && there.id == c.id)
        #expect(c.using(home) == c)
    }

    private typealias Device = CloudGatewayTests.Device

    private func syncBackups(_ d: Device, _ backups: Backups, listed: Set<String>) -> [UUID] {
        CloudAlternates.reconcile(store: d.store, storage: backups.storage, listedIDs: listed, defaults: d.defaults, now: d.cloud.tick())
    }
    final class Backups { var file: [String: CloudAlternates.Entry] = [:]
        var storage: CloudAlternates.Storage { .init(load: { self.file }, save: { self.file = $0 }) }
    }

    @Test func aBackupTravelsAndA20DeviceDoesNotDropIt() throws {
        let cloud = CloudGatewayTests.Cloud(), backups = Backups()
        let phone = Device(cloud), mac = Device(cloud)
        var g = GatewayConnection(name: "Home", gateway: home, authMode: .sessionToken)
        try phone.store.upsert(g, secrets: GatewaySecrets(sessionToken: "t"))
        phone.sync(); mac.sync()
        let ids = Set([g.id.uuidString])
        _ = syncBackups(phone, backups, listed: ids); _ = syncBackups(mac, backups, listed: ids)

        // The phone (21) adds a backup.
        g.alternate = away
        try phone.store.upsert(g, secrets: GatewaySecrets(sessionToken: "t"))
        phone.sync()
        #expect(cloud.file.gateways.allSatisfy { $0.connection.alternate == nil }, "the list a 20 device reads carries no backup")
        _ = syncBackups(phone, backups, listed: ids)
        #expect(syncBackups(mac, backups, listed: ids) == [g.id])
        #expect(mac.store.connection(id: g.id)?.alternate == away)

        // A 20 device writes the list back (it knows nothing of backups): nothing is lost.
        var rewritten = cloud.file
        for i in rewritten.gateways.indices { rewritten.gateways[i].connection.alternate = nil; rewritten.gateways[i].updatedAt += 0 }
        cloud.file = rewritten
        phone.sync(); mac.sync()
        _ = syncBackups(phone, backups, listed: ids); _ = syncBackups(mac, backups, listed: ids)
        #expect(phone.store.connection(id: g.id)?.alternate == away && mac.store.connection(id: g.id)?.alternate == away)

        // Removed on the Mac: removed on the phone.
        var onMac = try #require(mac.store.connection(id: g.id))
        onMac.alternate = nil
        try mac.store.upsert(onMac, secrets: GatewaySecrets(sessionToken: "t"))
        _ = syncBackups(mac, backups, listed: ids)
        #expect(syncBackups(phone, backups, listed: ids) == [g.id])
        #expect(phone.store.connection(id: g.id)?.alternate == nil)
        // And it settles: nothing moves on the next passes.
        #expect(syncBackups(phone, backups, listed: ids).isEmpty && syncBackups(mac, backups, listed: ids).isEmpty)
    }

    @Test func aNewDeviceTakesTheBackupItFinds() throws {
        let cloud = CloudGatewayTests.Cloud(), backups = Backups()
        let phone = Device(cloud), ipad = Device(cloud)
        var g = GatewayConnection(name: "Home", gateway: home, authMode: .sessionToken)
        g.alternate = away
        try phone.store.upsert(g, secrets: GatewaySecrets(sessionToken: "t"))
        phone.sync()
        let ids = Set([g.id.uuidString])
        _ = syncBackups(phone, backups, listed: ids)
        // The iPad has a gateway already (so it imports), and gets this one from the list.
        try ipad.store.upsert(GatewayConnection(name: "Lab", gateway: try GatewayURL.normalize("https://lab.example.com"), authMode: .sessionToken), secrets: GatewaySecrets(sessionToken: "u"))
        ipad.sync()
        #expect(ipad.store.connection(id: g.id)?.alternate == nil, "the list alone brings no backup")
        _ = syncBackups(ipad, backups, listed: ids)
        #expect(ipad.store.connection(id: g.id)?.alternate == away)
    }
}
