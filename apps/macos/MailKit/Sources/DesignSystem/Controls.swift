import SwiftUI

/// A key as it appears on the keyboard, next to every action that has one.
public struct KeyCap: View {
    private let key: String

    public init(_ key: String) {
        self.key = key
    }

    public var body: some View {
        Text(key)
            .font(.keyCap)
            .foregroundStyle(Color.textSecondary)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(Color.raised, in: .rect(cornerRadius: Metrics.keyCapRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.keyCapRadius).strokeBorder(Color.lineStrong))
    }
}

public struct MailButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary, ghost }

    private let kind: Kind
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.uiMedium)
            .lineLimit(1)
            .padding(.horizontal, kind == .ghost ? 8 : 12)
            .frame(height: Metrics.controlHeight)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed), in: .rect(cornerRadius: Metrics.controlRadius))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .onInverted
        case .secondary: .textPrimary
        case .ghost: isHovered ? .textPrimary : .textSecondary
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: .inverted.opacity(pressed ? 0.8 : isHovered ? 0.9 : 1)
        case .secondary, .ghost: pressed ? .selected : isHovered ? .hover : .clear
        }
    }
}

extension ButtonStyle where Self == MailButtonStyle {
    public static var primary: MailButtonStyle { MailButtonStyle(.primary) }
    public static var secondary: MailButtonStyle { MailButtonStyle(.secondary) }
    public static var ghost: MailButtonStyle { MailButtonStyle(.ghost) }
}

/// A small switch, blue when on.
public struct SwitchStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(configuration.isOn ? Color.accent : Color.lineStrong)
                .frame(width: 28, height: 16)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.white : Color.textMuted)
                        .frame(width: 12, height: 12)
                        .padding(2)
                }
                .animation(.enter, value: configuration.isOn)
            configuration.label
        }
        .contentShape(.rect)
        .onTapGesture { configuration.isOn.toggle() }
    }
}

extension ToggleStyle where Self == SwitchStyle {
    public static var mailSwitch: SwitchStyle { SwitchStyle() }
}

/// A bordered field for forms and inline inputs.
public struct FieldStyle: TextFieldStyle {
    public init() {}

    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.ui)
            .padding(.horizontal, 10)
            .frame(height: Metrics.controlHeight)
            .background(Color.canvas, in: .rect(cornerRadius: Metrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
    }
}

extension TextFieldStyle where Self == FieldStyle {
    public static var field: FieldStyle { FieldStyle() }
}

/// Initials in a circle. No photos and no generated gradients: a list of faces is noise.
public struct Avatar: View {
    private let name: String
    private let size: CGFloat

    public init(_ name: String, size: CGFloat = 28) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        Text(initials)
            .font(.geist(size * 0.38, .medium))
            .foregroundStyle(Color.textSecondary)
            .frame(width: size, height: size)
            .background(Color.selected, in: .circle)
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "@" })
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// A state, always paired with a word next to it.
public struct StatusDot: View {
    private let color: Color

    public init(_ color: Color) {
        self.color = color
    }

    public var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

/// The one-pixel line between regions.
public struct Hairline: View {
    private let axis: Axis

    public init(_ axis: Axis = .horizontal) {
        self.axis = axis
    }

    public var body: some View {
        Rectangle()
            .fill(Color.line)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}
