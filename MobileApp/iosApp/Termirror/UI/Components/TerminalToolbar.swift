import SwiftUI

struct TerminalToolbar: View {
    @Binding var controlLocked: Bool
    @Binding var altLocked: Bool
    let onKeyAction: (ToolbarKey) -> Void

    private let keyNormalBg = Color(red: 0.9, green: 0.957, blue: 0.918)
    private let keyActiveBg = Color(red: 0.122, green: 0.478, blue: 0.365)
    private let keyNormalFg = Color(red: 0.098, green: 0.529, blue: 0.333)
    private let keyActiveFg = Color.white

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(toolRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        let (key, label) = item
                        let isChecked = (key == .ctrl && controlLocked) || (key == .alt && altLocked)
                        Button(action: { onKeyAction(key) }) {
                            Group {
                                if key == .kbd {
                                    Image(systemName: "keyboard")
                                        .symbolRenderingMode(.monochrome)
                                } else {
                                    Text(label)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .allowsTightening(true)
                                        .underline(isChecked && (key == .ctrl || key == .alt))
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isChecked ? keyActiveFg : keyNormalFg)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(isChecked ? keyActiveBg : keyNormalBg)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(key == .kbd ? "terminalKeyboardButton" : "terminalKey_\(key.rawValue)")
                        .accessibilityLabel(key == .kbd ? "键盘" : label)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(keyNormalBg)
    }
}
