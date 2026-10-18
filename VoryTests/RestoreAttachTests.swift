import Foundation
import Network
import Testing
@testable import Vory
@testable import VoryCore

/// #422: a cold launch reopens the chat that was open (`AppRestore`), and the chat's attach can
/// fail before the socket is first up: a gateway unreachable then, or slower than the attach's
/// wait. The socket's first open did not re-attach anything (only a reconnect did), so the chat
/// showed its cached rows with no live attach and refused every send until it was closed and
/// opened again. Now a failed attach is tried again once the socket is up; a chat attached or
/// still attaching is left alone, and one the gateway does not have says so as it opens.
@MainActor @Suite struct RestoreAttachTests {
    private func chat(_ storedID: String = "s1") throws -> ChatSession {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        let rt = GatewayRuntime(connection: conn, store: ConnectionStore())
        return ChatSession(runtime: rt, storedID: storedID, title: nil)
    }

    private static let attached: JSONValue = .object(["session_id": .string("rt1"), "stored_session_id": .string("s1"), "messages": .array([])])

    @Test func aChatTheGatewayDoesNotHaveSaysSoAsItOpens() async throws {
        let c = try chat("gone-1")
        var resumes = 0
        c.gatewayStandIn = { method, _ in
            if method == "session.resume" { resumes += 1; throw RPCError(code: 4007, message: "session not found") }
            return .object([:])
        }
        c.beginResume()
        await c.awaitResume()
        #expect(c.resumeError != nil)
        #expect(c.banner == ChatSession.goneBanner, "no word that the chat is gone: \(c.banner ?? "nil")")
        // A connection coming up cannot bring it back: it is not tried again on its own.
        #expect(!c.retryFailedAttach())
        #expect(resumes == 1)
    }

    @Test func anAttachThatGaveUpWaitingIsTriedAgainAndTheChatSends() async throws {
        let c = try chat()
        var resumes = 0
        var submitted: [String] = []
        c.gatewayStandIn = { method, params in
            switch method {
            case "session.resume":
                resumes += 1
                if resumes == 1 { throw SocketError.timeout("gateway.ready") }
                return Self.attached
            case "prompt.submit":
                submitted.append(params["text"]?.stringValue ?? "")
                return .object([:])
            default:
                return .object([:])
            }
        }
        c.beginResume()
        await c.awaitResume()
        #expect(c.resumeError != nil)
        #expect(c.banner == nil, "a gateway that was not reachable yet is not a gone chat")
        #expect(await c.send("still there?") != nil, "a send while unattached is refused")

        #expect(c.retryFailedAttach())
        await c.awaitResume()
        #expect(c.resumeError == nil)
        #expect(c.runtimeID == "rt1")
        #expect(await c.send("still there?") == nil)
        #expect(submitted == ["still there?"])
        #expect(resumes == 2)
    }

    @Test func aChatAttachedOrStillAttachingIsLeftAlone() async throws {
        let c = try chat()
        var resumes = 0
        var hold: CheckedContinuation<Void, Never>?
        c.gatewayStandIn = { method, _ in
            guard method == "session.resume" else { return .object([:]) }
            resumes += 1
            await withCheckedContinuation { hold = $0 }
            return Self.attached
        }
        c.beginResume()
        while hold == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(c.isResuming)
        #expect(!c.retryFailedAttach(), "a chat still attaching was attached again")
        hold?.resume()
        await c.awaitResume()
        #expect(c.resumeError == nil)
        #expect(!c.retryFailedAttach(), "an attached chat was attached again")
        #expect(resumes == 1)
    }
}

/// The same through a real socket: the chat is opened with no gateway there, its attach gives up,
/// and the gateway comes up afterwards. The socket's first open attaches it, and replies and sends
/// go through without the chat being closed and opened again.
@MainActor @Suite(.serialized) struct RestoreFirstConnectTests {
    /// A gateway of our own on the loopback: says it is ready (after `readyDelay`), attaches any
    /// chat it is asked for (`session.resume`), and answers a sent message with a reply.
    final class FakeGateway: @unchecked Sendable {
        let listener: NWListener
        private let queue = DispatchQueue(label: "dev.vory.tests.fake-gateway")
        private var connections: [NWConnection] = []
        private var methods: [String] = []
        var resumes: Int { queue.sync { methods.filter { $0 == "session.resume" }.count } }
        var submits: Int { queue.sync { methods.filter { $0 == "prompt.submit" }.count } }

        init(port: UInt16, readyDelay: Double = 0) throws {
            let params = NWParameters.tcp
            let ws = NWProtocolWebSocket.Options()
            ws.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                if case .ready = state { ready.signal() }
                if case .failed = state { ready.signal() }
            }
            listener.newConnectionHandler = { [self] c in
                connections.append(c)
                c.stateUpdateHandler = { [self] state in
                    if case .ready = state {
                        queue.asyncAfter(deadline: .now() + readyDelay) { [self] in
                            send(["jsonrpc": "2.0", "method": "event", "params": ["type": "gateway.ready", "session_id": "", "payload": [:]]], on: c)
                        }
                    }
                }
                func receive() {
                    c.receiveMessage { [self] data, _, _, error in
                        guard error == nil else { return }
                        if let data { answer(data, on: c) }
                        receive()
                    }
                }
                c.start(queue: queue)
                receive()
            }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 5)
        }

        private func send(_ obj: [String: Any], on c: NWConnection) {
            guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "frame", metadata: [meta])
            c.send(content: data, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in })
        }

        private func answer(_ data: Data, on c: NWConnection) {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = obj["method"] as? String, let id = obj["id"] else { return }
            methods.append(method)
            let p = obj["params"] as? [String: Any] ?? [:]
            switch method {
            case "session.resume":
                let stored = p["session_id"] as? String ?? ""
                send(["jsonrpc": "2.0", "id": id, "result": ["session_id": "rt-" + stored, "stored_session_id": stored, "messages": []]], on: c)
            case "prompt.submit":
                let sid = p["session_id"] as? String ?? ""
                send(["jsonrpc": "2.0", "id": id, "result": [:]], on: c)
                send(["jsonrpc": "2.0", "method": "event", "params": ["type": "message.start", "session_id": sid, "payload": [:]]], on: c)
                send(["jsonrpc": "2.0", "method": "event", "params": ["type": "message.complete", "session_id": sid,
                                                                       "payload": ["text": "Back again.", "status": "complete"]]], on: c)
            default:
                send(["jsonrpc": "2.0", "id": id, "result": [:]], on: c)
            }
        }

        func stop() {
            listener.cancel()
            queue.sync { for c in connections { c.cancel() } }
        }
    }

    /// A loopback port with nothing on it yet.
    private func freePort() async throws -> UInt16 {
        let probe = try SocketTimeoutTests.SilentServer(greeting: nil)
        let port = probe.port
        probe.stop()
        try await Task.sleep(for: .milliseconds(300))
        return port
    }

    private func runtime(port: UInt16) throws -> GatewayRuntime {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("http://127.0.0.1:\(port)"), authMode: .sessionToken)
        return GatewayRuntime(connection: conn, store: ConnectionStore())
    }

    private func until(_ seconds: Double, _ condition: () -> Bool) async throws -> Bool {
        let began = Date()
        while Date().timeIntervalSince(began) < seconds {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test func aGatewayThatComesUpAfterTheAttachGaveUpAttachesTheReopenedChat() async throws {
        let port = try await freePort()
        let rt = try runtime(port: port)
        await rt.socket.connect()
        defer { Task { await rt.socket.disconnect() } }
        // The cold launch's restore: the chat opens with no gateway to attach it (a refused
        // connect fails a waiting attach at once; a gateway that never answers, after 20 s).
        let chat = try await rt.openChat(storedID: "s1", title: "Restored", profile: "default")
        await chat.awaitResume()
        #expect(chat.resumeError != nil, "the attach should have given up with no gateway there")

        // The gateway comes up: the socket's first open attaches the chat.
        let gateway = try FakeGateway(port: port)
        defer { gateway.stop() }
        let attached = try await until(10) { chat.resumeError == nil && !chat.isResuming && chat.runtimeID == "rt-s1" }
        #expect(attached, "the reopened chat was not attached once the gateway came up (\(chat.resumeError ?? "no error"))")
        #expect(gateway.resumes == 1)

        // It sends, and the reply arrives, without closing and opening the chat.
        #expect(await chat.send("still there?") == nil)
        let replied = try await until(5) {
            chat.items.contains { if case .assistant(let t, _, _) = $0.kind { t == "Back again." } else { false } }
        }
        #expect(replied, "the reply did not reach the reopened chat")
        #expect(gateway.submits == 1)
    }

    @Test func aChatStillAttachingWhenTheSocketFirstOpensIsAttachedOnce() async throws {
        // A gateway slow to say it is ready: the chat opens while the socket's first open is under
        // way, and its attach waits for it.
        let port = try await freePort()
        let gateway = try FakeGateway(port: port, readyDelay: 1.5)
        defer { gateway.stop() }
        let rt = try runtime(port: port)
        await rt.socket.connect()
        defer { Task { await rt.socket.disconnect() } }
        let chat = try await rt.openChat(storedID: "s2", title: nil, profile: "default")
        #expect(chat.isResuming)
        await chat.awaitResume()
        #expect(chat.resumeError == nil, "\(chat.resumeError ?? "")")
        // Left to finish rather than attached a second time by the first open.
        try await Task.sleep(for: .milliseconds(500))
        #expect(gateway.resumes == 1, "attached \(gateway.resumes) times")
    }
}
