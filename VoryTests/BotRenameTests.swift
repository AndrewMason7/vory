import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// Renaming a bot's folder (#315, part two): the name rules, what Vory refuses before asking
/// the gateway, what moves between Vory's own keys, and the gateway's two calls as the app
/// makes them (the OPTIONS probe for the route, the PATCH itself).
/// This suite's own fake transport: `MockURLProtocol` belongs to HermesAPITests, and two suites
/// sharing one static handler race when Swift Testing runs them side by side (seen on iOS).
final class RenameStubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { return }
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open(); var data = Data(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 4096); if n > 0 { data.append(buf, count: n) } else { break } }
            buf.deallocate(); stream.close(); req.httpBody = data
        }
        let (status, headers, body) = handler(req)
        let response = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct BotRenameTests {
    private let profiles = [ProfileInfo(name: "default", isDefault: true), ProfileInfo(name: "work"), ProfileInfo(name: "ops")]

    @Test func theNameIsCleanedLikeNewBot() {
        #expect(BotRename.cleaned("Ops Desk") == "ops-desk")
        #expect(BotRename.cleaned("  Night--Shift!  ") == "night-shift")
        #expect(BotRename.cleaned("a_b") == "a_b")
        #expect(BotRename.cleaned("---") == "")
    }

    @Test func refusalsComeBeforeTheGateway() {
        #expect(BotRename.refusal(renaming: "work", to: "Ops Desk", profiles: profiles, connected: "default") == nil)
        #expect(BotRename.refusal(renaming: "work", to: "", profiles: profiles, connected: nil) == .empty)
        #expect(BotRename.refusal(renaming: "work", to: "Work", profiles: profiles, connected: nil) == .same)
        #expect(BotRename.refusal(renaming: "work", to: "sudo", profiles: profiles, connected: nil) == .reserved)
        #expect(BotRename.refusal(renaming: "work", to: "Default", profiles: profiles, connected: nil) == .reserved)
        #expect(BotRename.refusal(renaming: "work", to: "ops", profiles: profiles, connected: nil) == .taken)
        #expect(BotRename.refusal(renaming: "default", to: "main", profiles: profiles, connected: nil) == .isDefault)
        // Vory reaches the gateway through this bot's own process: the rename would stop it for good.
        #expect(BotRename.refusal(renaming: "work", to: "ops2", profiles: profiles, connected: "work") == .connectedThroughIt)
        #expect(BotRename.refusal(renaming: "work", to: "ops2", profiles: profiles, connected: "default") == nil)
    }

    @Test func voryKeysFollowTheBot() {
        let old = "rn-old-\(UUID().uuidString.prefix(6).lowercased())", new = old + "-new"
        let suite = "bot-rename-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer {
            d.removePersistentDomain(forName: suite)
            var c = BotColors.stored(); c[old] = nil; c[new] = nil; BotColors.save(c)
            var a = BotAvatarStore.stored(); a[old] = nil; a[new] = nil; BotAvatarStore.save(a)
            BotAvatarStore.removePhoto(for: new)
        }
        BotNames.set(displayName: "Scribe", title: "Minutes", for: old, d)
        var colors = BotColors.stored(); colors[old] = "#123456"; BotColors.save(colors)
        var avatars = BotAvatarStore.stored(); avatars[old] = "photo"; BotAvatarStore.save(avatars)
        if let url = BotAvatarStore.photoURL(for: old) { try? Data([1, 2, 3]).write(to: url) }
        d.set(old, forKey: GatewayRuntime.defaultProfileKey)

        BotRename.moveLocalState(from: old, to: new, defaults: d)

        #expect(BotNames.names(for: new, d) == ProfileOwnNames(displayName: "Scribe", title: "Minutes"))
        #expect(BotNames.names(for: old, d) == nil)
        #expect(BotColors.stored()[new] == "#123456" && BotColors.stored()[old] == nil)
        #expect(BotAvatarStore.stored()[new] == "photo" && BotAvatarStore.stored()[old] == nil)
        #expect(BotAvatarStore.photoURL(for: new).map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(BotAvatarStore.photoURL(for: old).map { FileManager.default.fileExists(atPath: $0.path) } == false)
        #expect(d.string(forKey: GatewayRuntime.defaultProfileKey) == new)
    }

    @Test func aBotWithNothingKeptKeepsOnlyItsColour() {
        let suite = "bot-rename-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let old = "rn-none-\(UUID().uuidString.prefix(6).lowercased())", new = old + "-new"
        defer {
            d.removePersistentDomain(forName: suite)
            var c = BotColors.stored(); c[new] = nil; BotColors.save(c)
        }
        d.set("other", forKey: GatewayRuntime.defaultProfileKey)
        BotRename.moveLocalState(from: old, to: new, defaults: d)
        #expect(BotNames.names(for: new, d) == nil)
        #expect(BotAvatarStore.stored()[new] == nil)
        // The palette picks by name, so the colour it had is pinned under the new one.
        #expect(BotColors.stored()[new] == BotColors.defaultHex(for: old))
        #expect(d.string(forKey: GatewayRuntime.defaultProfileKey) == "other")
    }

    private func makeAPI() throws -> HermesAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RenameStubProtocol.self]
        let g = try GatewayURL.normalize("https://h.example.com/hermes")
        let signer = RequestSigner(authMode: .sessionToken, sessionToken: "tok")
        return HermesAPI(gateway: g, signer: signer, urlSession: URLSession(configuration: cfg))
    }

    @Test func theRouteIsOfferedOnlyWhenAllowNamesPatch() async throws {
        let api = try makeAPI()
        RenameStubProtocol.handler = { req in
            #expect(req.httpMethod == "OPTIONS")
            #expect(req.url?.path.hasSuffix("/api/profiles/_probe") == true)
            return (405, ["Allow": "PATCH"], Data())
        }
        #expect(await BotRename.supported(on: api))
        // An older gateway: the path exists for DELETE alone.
        RenameStubProtocol.handler = { _ in (405, ["Allow": "DELETE"], Data()) }
        #expect(await !BotRename.supported(on: api))
        // No such route at all, or a relay that carries no headers.
        RenameStubProtocol.handler = { _ in (404, ["Content-Type": "application/json"], Data(#"{"detail":"Not Found"}"#.utf8)) }
        #expect(await !BotRename.supported(on: api))
        RenameStubProtocol.handler = { _ in (405, [:], Data()) }
        #expect(await !BotRename.supported(on: api))
    }

    @Test func thePatchCarriesTheCleanedNameAndTheAnswerNamesTheFolder() async throws {
        let api = try makeAPI()
        RenameStubProtocol.handler = { req in
            #expect(req.httpMethod == "PATCH")
            #expect(req.url?.path.hasSuffix("/api/profiles/work") == true)
            let body = req.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            #expect(body?["new_name"]?.stringValue == "ops-desk")
            return (200, ["Content-Type": "application/json"], Data(#"{"ok":true,"name":"ops-desk","path":"/home/hermes/.hermes-ops-desk"}"#.utf8))
        }
        let r: JSONValue = try await api.send("PATCH", "/api/profiles/work", json: .object(["new_name": .string(BotRename.cleaned("Ops Desk"))]))
        #expect(r["name"]?.stringValue == "ops-desk")
        // A refusal from the gateway comes through with its reason.
        RenameStubProtocol.handler = { _ in (400, ["Content-Type": "application/json"], Data(#"{"detail":"Profile 'ops' already exists"}"#.utf8)) }
        await #expect(throws: HermesAPIError.self) {
            let _: JSONValue = try await api.send("PATCH", "/api/profiles/work", json: .object(["new_name": .string("ops")]))
        }
    }
}
