import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// Reasoning effort as its own item in the chat's menu (#301): which levels are listed, and
/// what the item says.
@Suite struct ReasoningEffortTests {
    @Test func theKnownLevelsAreListedByStrengthAndUnknownOnesAfter() {
        // Nothing from the gateway: the full known set, never three (#319).
        #expect(ReasoningEffort.levels(offered: nil) == ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"])
        #expect(ReasoningEffort.levels(offered: ["", "minimal", "low", "medium", "high", "xhigh", "max"]) == ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"])
        // Whatever order the gateway lists them in, the known ones go by strength; repeats and
        // blanks are dropped; a level only the gateway knows comes last, in the gateway's order.
        #expect(ReasoningEffort.levels(offered: ["max", " ", "high", "xhigh", "max"]) == ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"])
        #expect(ReasoningEffort.levels(offered: ["ultra", "max", "deep"]) == ["minimal", "low", "medium", "high", "xhigh", "max", "ultra", "deep"])
        // Hermes's full set, as its schema lists it, in one order whatever the gateway's (#319).
        #expect(ReasoningEffort.levels(offered: ["ultra", "xhigh", "", "minimal", "max", "high", "low", "medium"]) == ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"])
    }

    @Test func levelsReadAsWordsInTheMenuAndStayRawForTheGateway() {
        #expect(ReasoningEffort.name(of: "xhigh") == "Extra high")
        #expect(ReasoningEffort.name(of: "max") == "Max")
        #expect(ReasoningEffort.name(of: "ultra") == "Ultra")
        #expect(ReasoningEffort.name(of: "deep") == "Deep")
        #expect(ReasoningEffort.title(current: "xhigh") == "Reasoning: Extra high")
    }

    @Test func theTitleSaysTheLevelOrThatNoneIsSet() {
        #expect(ReasoningEffort.title(current: "medium") == "Reasoning: Medium")
        #expect(ReasoningEffort.title(current: nil) == "Reasoning: not set")
        #expect(ReasoningEffort.title(current: " ") == "Reasoning: not set")
    }

    @Test func theOfferedLevelsAreReadFromTheConfigSchema() throws {
        let json = #"{"fields": {"agent.reasoning_effort": {"type": "select", "options": ["", "low", "medium", "high", "max"]}, "model": {"type": "string"}}}"#
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(ReasoningEffort.offered(in: schema) == ["", "low", "medium", "high", "max"])
        // Hermes's real schema (#319): agent.reasoning_effort has a type but no options; the
        // delegation select carries the set.
        let real = #"{"fields": {"agent.reasoning_effort": {"type": "string", "category": "agent"}, "delegation.reasoning_effort": {"type": "select", "options": ["", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]}}}"#
        let hermes = try JSONDecoder().decode(JSONValue.self, from: Data(real.utf8))
        #expect(ReasoningEffort.offered(in: hermes) == ["", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"])
        #expect(ReasoningEffort.levels(offered: ReasoningEffort.offered(in: hermes)) == ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"])
        // Neither key, or a schema that could not be fetched: the full known set.
        let none = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"fields": {}}"#.utf8))
        #expect(ReasoningEffort.offered(in: none) == nil)
        #expect(ReasoningEffort.levels(offered: ReasoningEffort.offered(in: none)).count == 7)
    }
}
