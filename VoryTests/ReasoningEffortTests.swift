import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// Reasoning effort as its own item in the chat's menu (#301): which levels are listed, and
/// what the item says.
@Suite struct ReasoningEffortTests {
    @Test func theKnownLevelsAreListedByStrengthAndUnknownOnesAfter() {
        #expect(ReasoningEffort.levels(offered: nil) == ["low", "medium", "high"])
        #expect(ReasoningEffort.levels(offered: ["", "minimal", "low", "medium", "high", "xhigh", "max"]) == ["minimal", "low", "medium", "high", "xhigh", "max"])
        // Whatever order the gateway lists them in, the known ones go by strength; repeats and
        // blanks are dropped; a level only the gateway knows comes last, in the gateway's order.
        #expect(ReasoningEffort.levels(offered: ["max", " ", "high", "xhigh", "max"]) == ["low", "medium", "high", "xhigh", "max"])
        #expect(ReasoningEffort.levels(offered: ["ultra", "max", "deep"]) == ["low", "medium", "high", "max", "ultra", "deep"])
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
        let none = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"fields": {}}"#.utf8))
        #expect(ReasoningEffort.offered(in: none) == nil)
    }
}
