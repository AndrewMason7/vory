import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// The New Message composer's draft (#27): a chat that is not one yet. Its model and reasoning
/// picks stay on it, with nothing sent to the gateway (so nothing reaches another chat), and its
/// "/" list is the gateway's own, asked for without a session.
@MainActor @Suite struct ComposeDraftTests {
    private func runtime() throws -> GatewayRuntime {
        let conn = GatewayConnection(name: "unit", gateway: try GatewayURL.normalize("https://127.0.0.1:1"), authMode: .sessionToken)
        return GatewayRuntime(connection: conn, store: ConnectionStore())
    }

    @Test func aDraftKeepsItsPicksAndAsksTheGatewayNothing() async throws {
        let d = ChatSession.draft(runtime: try runtime(), profile: "work")
        var calls: [String] = []
        d.gatewayStandIn = { method, _ in calls.append(method); return .object([:]) }
        try await d.setModel(provider: "acme", model: "model-x")
        try await d.setReasoning("high")
        await d.switchModel(provider: "acme", model: "model-y")
        #expect(calls.isEmpty)
        #expect(d.isDraft)
        #expect(d.pendingModel == ChatSession.ModelPick(provider: "acme", model: "model-y"))
        #expect(d.modelName == "model-y")
        #expect(d.providerSlug == "acme")
        #expect(d.reasoningEffort == "high")
        // No line in a thread that does not exist.
        #expect(d.items.isEmpty)
    }

    @Test func aChatStillSetsItsReasoningOnTheGateway() async throws {
        let c = ChatSession(runtime: try runtime(), storedID: "s1", title: nil)
        var calls: [String] = []
        c.gatewayStandIn = { method, _ in calls.append(method); return .object([:]) }
        try await c.setReasoning("low")
        #expect(calls == ["config.set"])
        #expect(c.pendingReasoning == nil)
        #expect(!c.isDraft)
    }

    @Test func aDraftAsksForTheCatalogWithoutASession() async throws {
        let d = ChatSession.draft(runtime: try runtime(), profile: "work")
        var sent: [String: JSONValue]?
        d.gatewayStandIn = { _, params in sent = params; return .object([:]) }
        _ = await d.commandsCatalog()
        #expect(sent != nil)
        #expect(sent?["session_id"] == nil)
    }

    /// A group starts with words only (#32): the line under its message says the files stay behind
    /// and how to send them, in the singular for one.
    @Test func aGroupSaysItsFilesStayBehind() {
        #expect(NewChatSheet.groupFilesNote(count: 1) == "Group chats start with text only, so this file won't be sent. Remove a bot to send it.")
        #expect(NewChatSheet.groupFilesNote(count: 3) == "Group chats start with text only, so these files won't be sent. Remove a bot to send them.")
    }
}
