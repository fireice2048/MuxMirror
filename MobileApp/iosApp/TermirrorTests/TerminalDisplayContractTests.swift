import XCTest
@testable import Termirror

final class TerminalDisplayContractTests: XCTestCase {
    func testEncodesSgrAndX10WheelEvents() {
        XCTAssertEqual(encodeTerminalWheel(protocol: .sgr, direction: .up, column: 12, row: 7), "\u{001B}[<64;12;7M")
        XCTAssertEqual(encodeTerminalWheel(protocol: .sgr, direction: .down, column: -2, row: 0), "\u{001B}[<65;1;1M")
        XCTAssertEqual(encodeTerminalWheel(protocol: .x10, direction: .up, column: 1, row: 1), "\u{001B}[M`!!")
        XCTAssertEqual(encodeTerminalWheel(protocol: .none, direction: .up, column: 1, row: 1), "")
    }

    func testAccumulatesAndBoundsWheelSteps() {
        let pending = consumeTerminalWheelDelta(remainder: 0, deltaY: 20)
        XCTAssertEqual(pending.steps, 0)
        XCTAssertEqual(pending.remainder, 20)

        let upward = consumeTerminalWheelDelta(remainder: pending.remainder, deltaY: 40)
        XCTAssertEqual(upward.direction, .up)
        XCTAssertEqual(upward.steps, 2)
        XCTAssertEqual(upward.remainder, 4)

        let bounded = consumeTerminalWheelDelta(remainder: 0, deltaY: -300)
        XCTAssertEqual(bounded.direction, .down)
        XCTAssertEqual(bounded.steps, 4)
    }
}

final class MuxNavigationTests: XCTestCase {
    func testKeepsExpandedMuxRowsWhileKeyboardIsOpening() {
        XCTAssertEqual(
            effectiveMuxRows(
                muxAttached: true,
                rows: 19,
                keyboardVisible: false,
                keyboardRequestedVisible: true,
                expandedRows: 37
            ),
            37
        )
        XCTAssertEqual(
            effectiveMuxRows(
                muxAttached: true,
                rows: 19,
                keyboardVisible: true,
                keyboardRequestedVisible: false,
                expandedRows: 37
            ),
            37
        )
        XCTAssertEqual(
            effectiveMuxRows(
                muxAttached: false,
                rows: 19,
                keyboardVisible: true,
                keyboardRequestedVisible: true,
                expandedRows: 37
            ),
            19
        )
    }

    func testDeduplicatesAttachedClientsAcrossWindows() {
        let raw = #"{"windows":[{"title":"Terminal A","id":1,"tabs":[{"title":"tab-14","active":true,"mux":"TMUX","session":"tab-14","cwd":"~/Repo"}]},{"title":"Terminal B","id":2,"tabs":[{"title":"tab-14","active":false,"mux":"tmux","session":"tab-14","cwd":"~/Repo"}]}],"detached":[]}"#

        let result = parseMuxResult(raw, groupingMode: "window")

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.tabs.count, 1)
    }

    func testDirectoryModeUsesServerGroupTitleAndKeepsUniqueSessions() {
        let raw = #"{"windows":[{"title":"~/Repo/TermHook","id":1,"tabs":[{"title":"tab-14","active":true,"mux":"TMUX","session":"tab-14","cwd":"tab-14"},{"title":"tab-13","active":false,"mux":"TMUX","session":"tab-13","cwd":"tab-13"},{"title":"duplicate","active":false,"mux":"TMUX","session":"tab-14","cwd":"duplicate"}]}],"detached":[]}"#

        let result = parseMuxResult(raw, groupingMode: "directory", useServerDirectory: true)

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.title, "~/Repo/TermHook")
        XCTAssertEqual(result?.first?.tabs.count, 2)
    }

    func testAttachCommandRejectsNestedMuxAndNeverSwitchesClients() {
        let tmux = buildMuxAttachCommand(mux: "TMUX", session: "tab'14")
        let rmux = buildMuxAttachCommand(mux: "RMUX", session: "team")

        XCTAssertTrue(tmux.contains("if [ -n \"${TMUX-}${RMUX_SESSION-}${RMUX-}\" ]"))
        XCTAssertTrue(tmux.contains("exec tmux attach-session -f ignore-size -t 'tab'\"'\"'14'"))
        XCTAssertTrue(rmux.contains("exec rmux attach-session -f ignore-size -t 'team'"))
        XCTAssertTrue(tmux.contains("tmux refresh-client -t \"$client\" -D 999"))
        XCTAssertTrue(tmux.contains("SSH_TTY"))
        XCTAssertFalse(tmux.contains("switch-client"))
        XCTAssertFalse(rmux.contains("switch-client"))
    }
}
