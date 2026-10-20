import Foundation
import Testing
@testable import VoryCore

/// A gateway that answers one test at a time: a Hermes before the session fence or after it (#467), with what it was
/// asked kept in order.
final class FenceURLProtocol: URLProtocol {
    nonisolated(unsafe) static var gateway: FakeFenceGateway?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let gateway = Self.gateway else { return }
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open(); var data = Data(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 4096); if n > 0 { data.append(buf, count: n) } else { break } }
            buf.deallocate(); stream.close(); req.httpBody = data
        }
        let (status, body) = gateway.answer(req)
        let response = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class FakeFenceGateway: @unchecked Sendable {
    struct Asked { var method: String; var path: String; var query: [String: String]; var body: JSONValue? }
    let fenced: Bool
    var revision = 3
    var generation: Int?
    var exists = true
    /// The next edits refused with these details, in order.
    var refusals: [String] = []
    /// After a refusal, the chat's revision as another client left it.
    var revisionAfterRefusal: Int?
    /// The snapshot route answered with this instead (a catch-all route's `{}`, say).
    var snapshotBody: String?
    /// The DELETE answered with this instead (a chat already gone, or one the gateway cannot reach).
    var deleteAnswer: (Int, String)?
    private(set) var asked: [Asked] = []
    var edits: [Asked] { asked.filter { $0.method != "GET" } }

    init(fenced: Bool) { self.fenced = fenced }

    func answer(_ req: URLRequest) -> (Int, String) {
        let url = req.url!
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let body = req.httpBody.flatMap { $0.isEmpty ? nil : try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let path = url.path.replacingOccurrences(of: "/hermes", with: "")
        asked.append(Asked(method: req.httpMethod ?? "GET", path: path, query: query, body: body))
        if path.hasSuffix("/mutation-snapshot") {
            if let snapshotBody { return (200, snapshotBody) }
            guard fenced else { return (404, #"{"detail":"Not Found"}"#) }
            let gen = generation.map(String.init) ?? "null"
            return (200, #"{"session_id":"c1","exists":\#(exists),"runtime_revision":\#(exists ? revision : 0),"runtime_generation":\#(gen)}"#)
        }
        if req.httpMethod == "DELETE", let deleteAnswer { return deleteAnswer }
        guard fenced else { return (200, #"{"ok":true}"#) }
        let id = req.httpMethod == "DELETE" ? query["request_id"] : body?["request_id"]?.stringValue
        let rev = req.httpMethod == "DELETE" ? query["expected_revision"].flatMap(Int.init) : body?["expected_revision"]?.doubleValue.map(Int.init)
        if id == nil, rev == nil { return (409, #"{"detail":"client_upgrade_required: this app is out of sync (different versions) with the Hermes backend; update the app to edit sessions"}"#) }
        if !refusals.isEmpty {
            let r = refusals.removeFirst()
            if let moved = revisionAfterRefusal { revision = moved }
            return (409, #"{"detail":"\#(r)"}"#)
        }
        if rev != revision { return (409, #"{"detail":"revision_conflict"}"#) }
        if !exists { return req.httpMethod == "DELETE" ? (200, #"{"ok":true,"already_absent":true}"#) : (404, #"{"detail":"not_found"}"#) }
        revision += 1
        return (200, #"{"ok":true,"session_id":"c1","revision":\#(revision)}"#)
    }
}

@Suite(.serialized) struct SessionMutationTests {
    private func api(_ gateway: FakeFenceGateway) throws -> HermesAPI {
        FenceURLProtocol.gateway = gateway
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FenceURLProtocol.self]
        let g = try GatewayURL.normalize("https://h.example.com/hermes")
        return HermesAPI(gateway: g, signer: RequestSigner(authMode: .sessionToken, sessionToken: "tok"), urlSession: URLSession(configuration: cfg))
    }

    @Test func aHermesBeforeTheFenceGetsTodaysRequests() async throws {
        let gw = FakeFenceGateway(fenced: false)
        let api = try api(gw)
        try await SessionMutation.delete(api, id: "c1", profile: "work")
        try await SessionMutation.patch(api, id: "c1", profile: "work", fields: ["pinned": .bool(true)])
        #expect(gw.asked.filter { $0.path.hasSuffix("/mutation-snapshot") }.count == 2)
        let delete = try #require(gw.edits.first), patch = try #require(gw.edits.last)
        #expect(delete.method == "DELETE" && delete.query == ["profile": "work"])
        #expect(patch.method == "PATCH" && patch.body == .object(["pinned": .bool(true), "profile": .string("work")]))
    }

    @Test func aSnapshotWithoutTheRevisionIsNoFence() async throws {
        let gw = FakeFenceGateway(fenced: false); gw.snapshotBody = "{}"
        try await SessionMutation.delete(try api(gw), id: "c1", profile: "work")
        #expect(gw.edits.count == 1 && gw.edits.first?.query == ["profile": "work"])
    }

    @Test func aFencedDeleteCarriesItsIdentityInTheQuery() async throws {
        let gw = FakeFenceGateway(fenced: true)
        try await SessionMutation.delete(try api(gw), id: "c1", profile: "work")
        let d = try #require(gw.edits.first)
        #expect(gw.edits.count == 1 && d.method == "DELETE")
        #expect(d.query["expected_revision"] == "3" && d.query["profile"] == "work" && d.query["expected_generation"] == nil)
        #expect((d.query["request_id"] ?? "").count >= 8)
        // With a generation in the snapshot, it goes too.
        let gw2 = FakeFenceGateway(fenced: true); gw2.generation = 7
        try await SessionMutation.delete(try api(gw2), id: "c1", profile: "work")
        #expect(gw2.edits.first?.query["expected_generation"] == "7")
    }

    @Test func aFencedPatchCarriesItsIdentityInTheBody() async throws {
        let gw = FakeFenceGateway(fenced: true)
        try await SessionMutation.patch(try api(gw), id: "c1", profile: "work", fields: ["archived": .bool(true), "pinned": .bool(false)])
        let p = try #require(gw.edits.first)
        #expect(p.method == "PATCH" && p.query.isEmpty)
        #expect(p.body?["archived"] == .bool(true) && p.body?["pinned"] == .bool(false) && p.body?["profile"] == .string("work"))
        #expect(p.body?["expected_revision"] == .number(3) && p.body?["request_id"]?.stringValue?.isEmpty == false)
        #expect(p.body?["expected_generation"] == nil)
    }

    @Test func aChatThatMovedIsTriedOnceMoreWithANewSnapshotAndANewRequestID() async throws {
        let gw = FakeFenceGateway(fenced: true)
        gw.refusals = ["revision_conflict"]; gw.revisionAfterRefusal = 4
        try await SessionMutation.patch(try api(gw), id: "c1", profile: nil, fields: ["pinned": .bool(true)])
        #expect(gw.edits.count == 2)
        let first = try #require(gw.edits.first?.body), second = try #require(gw.edits.last?.body)
        #expect(first["expected_revision"] == .number(3) && second["expected_revision"] == .number(4))
        #expect(first["request_id"] != second["request_id"])
        #expect(gw.asked.filter { $0.path.hasSuffix("/mutation-snapshot") }.count == 2)
    }

    @Test func aSecondConflictIsSaidNotRetriedAgain() async throws {
        let gw = FakeFenceGateway(fenced: true)
        gw.refusals = ["stale_generation", "revision_conflict"]
        await #expect(throws: HermesAPIError.self) { try await SessionMutation.delete(try api(gw), id: "c1", profile: nil) }
        #expect(gw.edits.count == 2)
    }

    @Test func refusalsAreSaidInPlainWords() async throws {
        for (detail, words) in [("session_busy", "A turn is running in this chat"), ("unknown_execution", "its last turn was lost"),
                                ("runtime_draining", "Hermes is busy right now"), ("admission_conflict", "Try again")] {
            let gw = FakeFenceGateway(fenced: true); gw.refusals = [detail]
            do {
                try await SessionMutation.delete(try api(gw), id: "c1", profile: nil)
                Issue.record("\(detail) was not refused")
            } catch {
                #expect(SessionMutation.message(for: error)?.contains(words) == true, "\(detail): \(String(describing: SessionMutation.message(for: error)))")
                #expect(gw.edits.count == 1, "\(detail) was retried")
            }
        }
        let upgrade = HermesAPIError.http(status: 409, detail: "client_upgrade_required: this app is out of sync (different versions) with the Hermes backend; update the app to edit sessions")
        #expect(SessionMutation.refusal(upgrade) == .clientUpgradeRequired)
        #expect(SessionMutation.message(for: HermesAPIError.http(status: 500, detail: "boom")) == nil)
    }

    @Test func aChatAnOlderHermesNoLongerHasIsDeletedAlready() async throws {
        // Before the fence: a 404 to a DELETE is a chat already gone (deleted from another device first).
        let gw = FakeFenceGateway(fenced: false); gw.deleteAnswer = (404, #"{"detail":"Session not found"}"#)
        try await SessionMutation.delete(try api(gw), id: "c1", profile: nil)
        #expect(gw.edits.count == 1)
        // After it: a 404 not_found is a chat the gateway has but cannot reach, not deleted, and is said.
        let fenced = FakeFenceGateway(fenced: true); fenced.deleteAnswer = (404, #"{"detail":"not_found"}"#)
        await #expect(throws: HermesAPIError.self) { try await SessionMutation.delete(try api(fenced), id: "c1", profile: nil) }
    }

    @Test func aChatTheGatewayNoLongerHasIsDeletedAlready() async throws {
        let gw = FakeFenceGateway(fenced: true); gw.exists = false
        try await SessionMutation.delete(try api(gw), id: "c1", profile: nil)
        #expect(gw.edits.isEmpty)
        // A PATCH of one is the gateway's 404, which the list reads as a stale row.
        await #expect(throws: HermesAPIError.self) { try await SessionMutation.patch(try api(gw), id: "c1", profile: nil, fields: ["pinned": .bool(true)]) }
    }
}
