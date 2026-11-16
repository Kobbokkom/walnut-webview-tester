import Testing
@testable import wina

struct AgentApprovalModeTests {
    @Test func askAlwaysPrompts() {
        #expect(!AgentApprovalMode.ask.approvesWithoutAsking(.page))
        #expect(!AgentApprovalMode.ask.approvesWithoutAsking(.sensitive))
    }

    @Test func pageActionsCoverOnlyPageScope() {
        #expect(AgentApprovalMode.pageActions.approvesWithoutAsking(.page))
        #expect(!AgentApprovalMode.pageActions.approvesWithoutAsking(.sensitive))
    }

    @Test func allSkipsEveryPrompt() {
        #expect(AgentApprovalMode.all.approvesWithoutAsking(.page))
        #expect(AgentApprovalMode.all.approvesWithoutAsking(.sensitive))
    }
}
