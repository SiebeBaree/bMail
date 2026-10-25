import DesignSystem
import SwiftUI

/// A field sized for a thumb: 52 points tall, on a raised surface with a hairline border.
struct PhoneFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.phone(17))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.raised, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lineStrong))
    }
}

/// The full-width buttons on the welcome screen and in server setup.
struct PhoneButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    init(_ kind: Kind) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.phone(17, .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(kind == .primary ? Color.onInverted : Color.textPrimary)
            .background(kind == .primary ? Color.inverted : Color.raised, in: .rect(cornerRadius: 14))
            .overlay {
                if kind == .secondary { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.lineStrong) }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.rect(cornerRadius: 14))
    }
}
