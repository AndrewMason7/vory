import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// #283 against the mock on two ports (one process, so one gateway at two addresses):
///   mock_gateway.py --port 9132 --port2 9134 --token mock-token
/// (other ports: VORY_TWO_PORT_MOCK="a,b"). Skipped when the mock is not there. Times are
/// printed: time to connected on a cold open in both orders, and to the other address after
/// the one in use goes away.
@Suite(.serialized) struct BackupAddressIntegrationTests {
    static var ports: (Int, Int) {
        let raw = ProcessInfo.processInfo.environment["VORY_TWO_PORT_MOCK"] ?? "9132,9134"
        let p = raw.split(separator: ",").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : (9132, 9134)
    }

    static func answers(_ port: Int) async -> Bool {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/status")!, timeoutInterval: 1)
        r.httpMethod = "GET"
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// Takes one of the mock's ports down or up, asking through the other.
    static func port(_ port: Int, up: Bool, via other: Int) async {
        let url = URL(string: "http://127.0.0.1:\(other)/mock/port-\(up ? "up" : "down")?port=\(port)")!
        _ = try? await URLSession.shared.data(from: url)
        for _ in 0..<20 where await answers(port) != up { try? await Task.sleep(for: .milliseconds(100)) }
    }

    @MainActor static func runtime(_ primary: GatewayURL, _ backup: GatewayURL, lastGood: Int) async -> GatewayRuntime {
        let conn = GatewayConnection(name: "e2e two addresses", gateway: primary, authMode: .sessionToken, alternate: backup)
        AddressMemory().setLastGood(lastGood, for: conn.id)
        let rt = GatewayRuntime(connection: conn, store: ConnectionStore())
        await rt.replaceSecrets(GatewaySecrets(sessionToken: "mock-token"))
        return rt
    }

    /// Seconds until the runtime is connected at `address` (nil past `limit`).
    @MainActor static func connected(_ rt: GatewayRuntime, at address: GatewayURL, limit: Double = 15) async -> Double? {
        let start = Date()
        while Date().timeIntervalSince(start) < limit {
            if rt.socketState.isOpen, rt.address == address { return Date().timeIntervalSince(start) }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    @MainActor @Test func coldOpensAndSwitchesBetweenTwoAddresses() async throws {
        let (a, b) = Self.ports
        guard await Self.answers(a), await Self.answers(b) else { return }
        let home = try GatewayURL.normalize("http://127.0.0.1:\(a)"), away = try GatewayURL.normalize("http://127.0.0.1:\(b)")
        defer { Task { await Self.port(a, up: true, via: b); await Self.port(b, up: true, via: a) } }

        // A cold open on each address, as the one that worked last.
        for (i, address) in [home, away].enumerated() {
            let rt = await Self.runtime(home, away, lastGood: i)
            let t = await Self.connected(rt, at: address)
            print("[#283] cold open, last good \(address.description): connected in \(t.map { String(format: "%.2f s", $0) } ?? "never")")
            #expect(t != nil && t! < 3, "connected at the address that worked last")
            await rt.stop()
        }

        // The one in use goes away (its sockets closed, as the mock's port goes): the reconnect
        // finds the other within a few seconds, and back again.
        let rt = await Self.runtime(home, away, lastGood: 0)
        #expect(await Self.connected(rt, at: home) != nil)
        var t0 = Date()
        await Self.port(a, up: false, via: b)
        let toAway = await Self.connected(rt, at: away).map { _ in Date().timeIntervalSince(t0) }
        print("[#283] home address gone while connected: on the backup \(toAway.map { String(format: "%.2f s", $0) } ?? "never") after the port went")
        #expect(toAway != nil && toAway! < 5)
        await Self.port(a, up: true, via: b)
        t0 = Date()
        await Self.port(b, up: false, via: a)
        let toHome = await Self.connected(rt, at: home).map { _ in Date().timeIntervalSince(t0) }
        print("[#283] backup gone while connected: back home \(toHome.map { String(format: "%.2f s", $0) } ?? "never") after the port went")
        #expect(toHome != nil && toHome! < 5)
        await Self.port(b, up: true, via: a)
        // A change of network that leaves the socket answering moves nothing.
        await rt.networkChanged()
        #expect(rt.socketState.isOpen && rt.address == home)
        await rt.stop()
    }

    @MainActor @Test func aColdOpenAwayDoesNotWaitForTheHomeAddress() async throws {
        let (a, b) = Self.ports
        guard await Self.answers(b) else { return }
        _ = a
        // A home address that does not answer at all from here (nothing routes to it): the
        // probe would wait out its whole timeout; the head start is all it gets.
        let unreachable = try GatewayURL.normalize("http://10.255.255.1:9119")
        let away = try GatewayURL.normalize("http://127.0.0.1:\(b)")
        let first = await Self.runtime(unreachable, away, lastGood: 0)
        let t = await Self.connected(first, at: away)
        print("[#283] cold open away (home last good, home silent): connected in \(t.map { String(format: "%.2f s", $0) } ?? "never")")
        #expect(t != nil && t! < 2, "the backup answered; the silent home address held it only for its head start")
        await first.stop()
        // The other order: the backup was last good, so it is tried first and answers at once.
        let second = await Self.runtime(unreachable, away, lastGood: 1)
        let t2 = await Self.connected(second, at: away)
        print("[#283] cold open away (backup last good): connected in \(t2.map { String(format: "%.2f s", $0) } ?? "never")")
        #expect(t2 != nil && t2! < 2)
        await second.stop()
    }
}
