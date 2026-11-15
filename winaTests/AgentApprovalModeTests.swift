import Testing
@testable import wina

struct AgentApprovalModeTests {
    @Test func askAlwaysPrompts() {
        #expect(!AgentApprovalMode.ask.approvesWithoutAsking(tool: "page_interact", arguments: [:]))
    }

    @Test func pageActionsCoverPageToolsOnly() {
        let mode = AgentApprovalMode.pageActions
        #expect(mode.approvesWithoutAsking(tool: "page_interact", arguments: [:]))
        #expect(mode.approvesWithoutAsking(tool: "console_list", arguments: [:]))
        #expect(!mode.approvesWithoutAsking(tool: "walnut_screenshot", arguments: [:]))
        #expect(!mode.approvesWithoutAsking(tool: "settings_apply", arguments: [:]))
        #expect(!mode.approvesWithoutAsking(tool: "walnut_browser", arguments: ["cleanStart": true]))
        #expect(mode.approvesWithoutAsking(tool: "walnut_browser", arguments: ["action": "open"]))
    }

    @Test func allSkipsEveryPrompt() {
        #expect(AgentApprovalMode.all.approvesWithoutAsking(tool: "walnut_screenshot", arguments: [:]))
    }
}
