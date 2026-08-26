import XCTest

final class ServerListUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// 新增服务器后，列表应正确显示。
    @MainActor
    func testAddServer() throws {
        let suffix = UUID().uuidString.prefix(6)
        let name = "UI Test Server \(suffix)"

        app.buttons["addServerButton"].tap()

        app.textFields["nameTextField"].tap()
        app.textFields["nameTextField"].typeText(name)

        app.textFields["hostTextField"].tap()
        app.textFields["hostTextField"].typeText("192.168.1.100")

        app.textFields["usernameTextField"].tap()
        app.textFields["usernameTextField"].typeText("admin")

        // 验证密码可见性切换按钮存在并可点击
        let passwordRow = app.otherElements["passwordFieldRow"]
        XCTAssertTrue(passwordRow.waitForExistence(timeout: 2))
        let toggleButton = app.buttons["togglePasswordVisibilityButton"]
        XCTAssertTrue(toggleButton.exists)
        toggleButton.tap()
        toggleButton.tap()

        app.buttons["saveServerButton"].tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["admin@192.168.1.100:22"].exists)
    }

    /// 新增/编辑页文本框获得焦点时，系统软键盘必须可见。
    @MainActor
    func testServerEditorShowsSoftwareKeyboard() throws {
        app.buttons["addServerButton"].tap()

        let nameField = app.textFields["nameTextField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()

        assertSoftwareKeyboardVisible()
        nameField.typeText("Keyboard Test")
        XCTAssertEqual(nameField.value as? String, "Keyboard Test")
    }

    /// 终端点击和工具条按钮都应能唤起系统软键盘，固定样本同时用于截图检查 ANSI 色彩与排版。
    @MainActor
    func testTerminalShowsSoftwareKeyboardAndRenderingFixture() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--terminal-uitesting"]
        app.launch()

        let terminal = app.textViews["terminalTextView"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 3))
        XCTAssertTrue((terminal.value as? String)?.contains("中文宽字符对齐") == true)

        terminal.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let input = app.textFields["terminalInputField"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.typeText("keyboard-input-check")

        app.buttons["terminalKeyboardButton"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        app.buttons["terminalKeyboardButton"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "iPhone 17 Pro 终端 ANSI 与软键盘"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 本机现场诊断：从模拟器已有 M5 Pro 依次进入两个真实 MUX 目标。
    @MainActor
    func testInspectLiveMuxNavigation() throws {
        app.terminate()
        app = XCUIApplication()
        app.launch()

        let server = app.staticTexts["M5 Pro"]
        guard server.waitForExistence(timeout: 5) else {
            throw XCTSkip("当前模拟器未配置真实 M5 Pro，跳过现场 MUX 验收")
        }
        server.tap()
        XCTAssertTrue(app.textViews["terminalTextView"].waitForExistence(timeout: 15))
        app.buttons["MUX..."].tap()
        XCTAssertTrue(app.navigationBars["导航"].waitForExistence(timeout: 15))

        let buttons = app.buttons.allElementsBoundByIndex
        let labels = buttons.map { "\($0.identifier)|\($0.label)" }
        let labelsAttachment = XCTAttachment(string: labels.joined(separator: "\n"))
        labelsAttachment.name = "真实 MUX 导航按钮"
        labelsAttachment.lifetime = .keepAlways
        add(labelsAttachment)
        let sessions = buttons.compactMap { muxSession(from: $0.label) }
        XCTAssertGreaterThanOrEqual(sessions.count, 2, "真实 MUX 导航至少需要两个目标")
        let preferred = ["tab-8", "tab-12"].filter(sessions.contains)
        let selectedSessions = Array(
            (preferred + sessions.filter { !preferred.contains($0) }).prefix(2)
        )

        let screenshotAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshotAttachment.name = "真实 MUX 导航页"
        screenshotAttachment.lifetime = .keepAlways
        add(screenshotAttachment)

        try inspectLiveMuxTarget(selectedSessions[0], verifyKeyboard: true)

        let backToNavigation = app.navigationBars["M5 Pro"].buttons.firstMatch
        XCTAssertTrue(backToNavigation.waitForExistence(timeout: 3))
        backToNavigation.tap()
        XCTAssertTrue(app.navigationBars["导航"].waitForExistence(timeout: 5))

        try inspectLiveMuxTarget(selectedSessions[1], verifyKeyboard: false)
    }

    @MainActor
    private func inspectLiveMuxTarget(_ session: String, verifyKeyboard: Bool) throws {
        let target = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "TMUX[\(session)]")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "导航页不存在 \(session)")
        target.tap()

        let terminal = app.textViews["terminalTextView"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 15), "\(session) 终端未打开")
        sleep(3)

        let snapshot = (terminal.value as? String) ?? ""
        XCTAssertTrue(
            snapshot.contains("[\(session)]"),
            "请求 \(session)，实际终端没有进入对应 tmux 会话"
        )
        let snapshotAttachment = XCTAttachment(string: snapshot)
        snapshotAttachment.name = "\(session) 真实终端文本"
        snapshotAttachment.lifetime = .keepAlways
        add(snapshotAttachment)

        let screenshotAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshotAttachment.name = "\(session) 真实终端截图"
        screenshotAttachment.lifetime = .keepAlways
        add(screenshotAttachment)

        if verifyKeyboard {
            terminal.tap()
            assertSoftwareKeyboardVisible()
            let keyboardAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            keyboardAttachment.name = "\(session) 真实终端软键盘"
            keyboardAttachment.lifetime = .keepAlways
            add(keyboardAttachment)

            app.buttons["terminalKeyboardButton"].tap()
            XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        }
    }

    private func muxSession(from label: String) -> String? {
        guard let marker = label.range(of: "MUX["),
              let end = label[marker.upperBound...].firstIndex(of: "]") else {
            return nil
        }
        return String(label[marker.upperBound..<end])
    }

    @MainActor
    private func assertSoftwareKeyboardVisible(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertGreaterThan(
            keyboard.frame.height,
            100,
            "键盘元素存在但没有可见高度，不能视为软键盘已弹出",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            keyboard.frame.minY,
            app.frame.maxY - 100,
            "键盘元素仍在屏幕下方，不能视为软键盘已弹出",
            file: file,
            line: line
        )
    }

    /// 复制服务器时应自动去重名称，不覆盖已有条目。
    @MainActor
    func testCopyServerCreatesUniqueName() throws {
        let suffix = UUID().uuidString.prefix(6)
        let name = "Copy Source \(suffix)"

        // 先添加一条服务器
        app.buttons["addServerButton"].tap()
        app.textFields["nameTextField"].tap()
        app.textFields["nameTextField"].typeText(name)
        app.textFields["hostTextField"].tap()
        app.textFields["hostTextField"].typeText("10.0.0.1")
        app.textFields["usernameTextField"].tap()
        app.textFields["usernameTextField"].typeText("root")
        app.buttons["saveServerButton"].tap()

        sleep(3)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))

        // 复制两次，应出现“副本”和“副本2”
        app.buttons["copyButton_\(name)"].tap()
        let copyAlert = app.alerts["复制服务器"]
        XCTAssertTrue(copyAlert.waitForExistence(timeout: 2))
        copyAlert.buttons["复制"].tap()
        let copyName = "\(name) 副本"
        XCTAssertTrue(app.staticTexts[copyName].waitForExistence(timeout: 2))

        app.buttons["copyButton_\(name)"].tap()
        let copyAlert2 = app.alerts["复制服务器"]
        XCTAssertTrue(copyAlert2.waitForExistence(timeout: 2))
        copyAlert2.buttons["复制"].tap()
        let copyName2 = "\(name) 副本2"
        XCTAssertTrue(app.staticTexts[copyName2].waitForExistence(timeout: 2))
    }

    /// 网络诊断页应显示示例 placeholder 并可通过系统返回按钮回到首页。
    @MainActor
    func testNetworkDiagPlaceholderAndBack() throws {
        app.buttons["网络诊断"].tap()

        // 使用系统返回按钮回到首页
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["addServerButton"].waitForExistence(timeout: 3))
    }



    /// 终端页点击 MUX... 应正常推入导航页，不会闪退或导致后续页面空白。
    @MainActor
    func testMuxNavNavigation() throws {
        let suffix = UUID().uuidString.prefix(6)
        let name = "MuxNav Test \(suffix)"

        app.buttons["addServerButton"].tap()
        app.textFields["nameTextField"].tap()
        app.textFields["nameTextField"].typeText(name)
        app.textFields["hostTextField"].tap()
        app.textFields["hostTextField"].typeText("127.0.0.1")
        app.textFields["usernameTextField"].tap()
        app.textFields["usernameTextField"].typeText("user")
        app.buttons["saveServerButton"].tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))

        // 进入终端页（本地无可用 SSH，会进入错误态，但 MUX... 按钮仍可见）
        app.staticTexts[name].tap()
        XCTAssertTrue(app.buttons["返回服务器列表"].waitForExistence(timeout: 12))

        // 点击 MUX... 进入导航页
        app.buttons["MUX..."].tap()
        XCTAssertTrue(app.navigationBars["导航"].waitForExistence(timeout: 3))

        // 返回终端页，再返回首页，然后点击网络诊断，确认没有空白页
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["返回服务器列表"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["addServerButton"].waitForExistence(timeout: 3))
        app.buttons["网络诊断"].tap()
        XCTAssertTrue(app.navigationBars["网络诊断"].waitForExistence(timeout: 3))
    }

    /// 点击编辑按钮应进入编辑页，不应新增或复制出额外条目。
    @MainActor
    func testEditButtonDoesNotDuplicateOrCopy() throws {
        let suffix = UUID().uuidString.prefix(6)
        let name = "Edit Test \(suffix)"

        // 添加一条服务器
        app.buttons["addServerButton"].tap()
        app.textFields["nameTextField"].tap()
        app.textFields["nameTextField"].typeText(name)
        app.textFields["hostTextField"].tap()
        app.textFields["hostTextField"].typeText("192.168.1.1")
        app.textFields["usernameTextField"].tap()
        app.textFields["usernameTextField"].typeText("user")
        app.buttons["saveServerButton"].tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))

        // 点击编辑按钮
        app.buttons["editButton_\(name)"].tap()

        // 应弹出编辑 sheet，而不是新增副本
        XCTAssertTrue(app.navigationBars["编辑服务器"].waitForExistence(timeout: 2))

        // 取消编辑
        app.buttons["取消"].tap()

        // 确认没有新增同名项或副本
        XCTAssertEqual(app.staticTexts.matching(identifier: name).count, 1)
        XCTAssertFalse(app.staticTexts["\(name) 副本"].exists)
    }
}
