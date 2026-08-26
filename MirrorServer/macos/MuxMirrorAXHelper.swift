import ApplicationServices
import Cocoa

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

let separator = "\u{1f}"
let terminalBundles: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "com.mitchellh.ghostty",
    "dev.warp.Warp-Stable",
    "org.alacritty",
    "net.kovidgoyal.kitty",
    "com.github.wez.wezterm",
]

func isAccessibilityTrusted(prompt: Bool) -> Bool {
    if !prompt {
        return AXIsProcessTrusted()
    }
    let options = [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func handlePermissionCommand() -> Bool {
    let arguments = CommandLine.arguments.dropFirst()
    if arguments.contains("--check-permission") {
        let trusted = isAccessibilityTrusted(prompt: false)
        print(trusted ? "trusted" : "untrusted")
        exit(trusted ? EXIT_SUCCESS : 2)
    }
    if arguments.contains("--request-permission") {
        let trusted = isAccessibilityTrusted(prompt: true)
        print(trusted ? "trusted" : "untrusted")
        exit(trusted ? EXIT_SUCCESS : 2)
    }
    return false
}

func axAttribute(_ element: AXUIElement, _ name: String) -> Any? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return error == .success ? value : nil
}

func axString(_ element: AXUIElement, _ name: String) -> String {
    (axAttribute(element, name) as? String) ?? ""
}

func axSize(_ element: AXUIElement) -> (CGFloat, CGFloat) {
    guard let value = axAttribute(element, "AXSize") else { return (0, 0) }
    var size = CGSize.zero
    AXValueGetValue(value as! AXValue, .cgSize, &size)
    return (size.width, size.height)
}

func windowID(_ element: AXUIElement) -> UInt32 {
    var id: CGWindowID = 0
    _ = _AXUIElementGetWindow(element, &id)
    return id
}

func axInt(_ element: AXUIElement, _ name: String) -> Int {
    guard let value = axAttribute(element, name) else { return 0 }
    if let number = value as? Int { return number }
    if let boolean = value as? Bool { return boolean ? 1 : 0 }
    return 0
}

func axPositionX(_ element: AXUIElement) -> CGFloat {
    guard let value = axAttribute(element, "AXPosition") else { return 0 }
    var point = CGPoint.zero
    AXValueGetValue(value as! AXValue, .cgPoint, &point)
    return point.x
}

func findDocument(_ element: AXUIElement) -> String {
    if axString(element, "AXRole") == "AXTextArea" {
        let document = axString(element, "AXDocument")
        if !document.isEmpty { return document }
    }
    if let children = axAttribute(element, "AXChildren") as? [AXUIElement] {
        for child in children {
            let result = findDocument(child)
            if !result.isEmpty { return result }
        }
    }
    return ""
}

func enumerateTabs(_ window: AXUIElement, deepScan: Bool) -> [(String, Bool, String)] {
    var result: [(String, Bool, String, CGFloat)] = []
    guard let children = axAttribute(window, "AXChildren") as? [AXUIElement] else {
        return []
    }

    var tabButtons: [AXUIElement] = []
    for child in children {
        guard axString(child, "AXRole") == "AXTabGroup" else { continue }
        tabButtons = (axAttribute(child, "AXChildren") as? [AXUIElement]) ?? []
        break
    }
    guard !tabButtons.isEmpty else { return [] }

    var originalActiveIndex: Int?
    for (index, button) in tabButtons.enumerated() {
        guard axString(button, "AXRole") == "AXRadioButton" else { continue }
        let help = axString(button, "AXHelp")
        let title = axString(button, "AXTitle")
        let description = axString(button, "AXDescription")
        let displayedTitle = !help.isEmpty ? help : (!title.isEmpty ? title : description)
        let active = axInt(button, "AXValue") == 1
        if active { originalActiveIndex = index }

        var document = ""
        if active {
            document = findDocument(window)
        } else if deepScan && tabButtons.count > 1 {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.05)
            document = findDocument(window)
        }
        if !displayedTitle.isEmpty {
            result.append((displayedTitle, active, document, axPositionX(button)))
        }
    }

    if let originalIndex = originalActiveIndex, originalIndex < tabButtons.count {
        let currentIndex = tabButtons.firstIndex { axInt($0, "AXValue") == 1 } ?? -1
        if currentIndex != originalIndex {
            AXUIElementPerformAction(tabButtons[originalIndex], kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    result.sort { $0.3 < $1.3 }
    return result.map { ($0.0, $0.1, $0.2) }
}

func enumerateTerminalWindows() {
    guard isAccessibilityTrusted(prompt: false) else {
        fputs("MUXMIRROR_PERMISSION_REQUIRED\n", stderr)
        exit(77)
    }

    for application in NSWorkspace.shared.runningApplications {
        guard application.activationPolicy == .regular else { continue }
        let bundleID = application.bundleIdentifier ?? ""
        guard terminalBundles.contains(bundleID) else { continue }
        let processID = application.processIdentifier
        guard processID > 0 else { continue }

        let axApplication = AXUIElementCreateApplication(processID)
        var windowsReference: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            axApplication,
            "AXWindows" as CFString,
            &windowsReference
        )
        guard error == .success,
              let windows = windowsReference as? [AXUIElement]
        else { continue }

        for window in windows {
            let title = axString(window, "AXTitle")
            let (width, height) = axSize(window)
            let tabs = enumerateTabs(window, deepScan: bundleID == "com.googlecode.iterm2")
            var fields = [
                application.localizedName ?? "",
                String(processID),
                title,
                String(windowID(window)),
                String(Int(width)),
                String(Int(height)),
            ]
            for (tabTitle, focused, document) in tabs {
                fields.append((focused ? "*" : "") + tabTitle)
                fields.append(document)
            }
            print(fields.joined(separator: separator))
        }
    }
}

_ = handlePermissionCommand()
enumerateTerminalWindows()
