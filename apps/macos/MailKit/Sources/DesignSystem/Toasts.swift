import Observation
import SwiftUI

/// A short message about something that just happened, with at most one next step.
public struct Toast: Identifiable {
    public enum Tone: Sendable { case neutral, success, failure }

    public struct Action {
        public var title: String
        public var key: String?
        public var perform: @MainActor () -> Void

        public init(_ title: String, key: String? = nil, perform: @escaping @MainActor () -> Void) {
            self.title = title
            self.key = key
            self.perform = perform
        }
    }

    public let id = UUID()
    public var symbol: String
    public var tone: Tone
    public var title: String
    public var detail: String?
    public var action: Action?
    public var duration: Duration

    public init(
        _ title: String, detail: String? = nil, symbol: String = "checkmark", tone: Tone = .neutral,
        action: Action? = nil, duration: Duration = .seconds(5)
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
        self.action = action
        self.duration = duration
    }
}

@MainActor
@Observable
public final class ToastCenter {
    public private(set) var toasts: [Toast] = []

    public init() {}

    /// Shows a toast and removes it after its duration. At most three at a time; the oldest goes first.
    public func show(_ toast: Toast) {
        toasts.append(toast)
        if toasts.count > 3 { toasts.removeFirst() }
        Task {
            try? await Task.sleep(for: toast.duration)
            dismiss(toast.id)
        }
    }

    public func dismiss(_ id: Toast.ID) {
        toasts.removeAll { $0.id == id }
    }

    public func update(_ id: Toast.ID, title: String) {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else { return }
        toasts[index].title = title
    }

    /// Runs the action of the newest toast that has one. Bound to the toast's key, usually Z for undo.
    @discardableResult
    public func performLatestAction(key: String) -> Bool {
        guard let toast = toasts.last(where: { $0.action?.key == key }), let action = toast.action else { return false }
        action.perform()
        dismiss(toast.id)
        return true
    }
}

public struct ToastStack: View {
    @Bindable private var center: ToastCenter

    public init(_ center: ToastCenter) {
        self.center = center
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(center.toasts) { toast in
                ToastView(toast: toast) { center.dismiss(toast.id) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.enter, value: center.toasts.map(\.id))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.rowIcon.weight(.medium))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            (Text(toast.title).foregroundStyle(Color.textPrimary)
                + Text(toast.detail.map { " \($0)" } ?? "").foregroundStyle(Color.textMuted))
                .font(.ui)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action = toast.action {
                Button {
                    action.perform()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text(action.title)
                        if let key = action.key { KeyCap(key) }
                    }
                }
                .buttonStyle(.secondary)
                .controlSize(.small)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(width: 400, alignment: .leading)
        .frame(minHeight: 46)
        .background(Color.raised, in: .rect(cornerRadius: Metrics.popoverRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.popoverRadius).strokeBorder(Color.lineStrong))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        switch toast.tone {
        case .neutral: .textSecondary
        case .success: .success
        case .failure: .danger
        }
    }
}
