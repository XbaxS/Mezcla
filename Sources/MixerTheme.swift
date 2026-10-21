import SwiftUI

/// Drumline / Concrete palette, shared by the window and menu bar popover.
enum MixerTheme {
    static let background = Color(hex: 0x111827)
    static let slate = Color(hex: 0x374151)
    static let secondary = Color(hex: 0x9CA3AF)
    static let accent = Color(hex: 0xF97316)
    static let text = Color(hex: 0xF3F4F6)
    static let width: CGFloat = 480
    static let height: CGFloat = 700
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

struct MixerButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? MixerTheme.background : MixerTheme.text)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(prominent ? MixerTheme.accent : MixerTheme.slate, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
