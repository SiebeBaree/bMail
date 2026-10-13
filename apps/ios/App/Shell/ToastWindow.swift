import DesignSystem
import SwiftUI
import UIKit

/// Shows toasts in a window of their own above the app, so they stay visible over sheets like the composer. The window
/// only takes touches inside the toast on screen; everything else falls through to the app below. SwiftUI's own hit
/// testing can't say that: it claims every point of its window.
struct ToastWindow: UIViewRepresentable {
    let center: ToastCenter

    func makeUIView(context: Context) -> Anchor { Anchor(center: center) }
    func updateUIView(_ view: Anchor, context: Context) {}

    final class Anchor: UIView {
        private let toasts: ToastCenter
        private var overlay: UIWindow?

        init(center: ToastCenter) {
            self.toasts = center
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("Not used from a storyboard") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard overlay == nil, let scene = window?.windowScene else { return }
            let hitArea = HitArea()
            let host = UIHostingController(rootView: ToastStackView(center: toasts, hitArea: hitArea))
            host.view.backgroundColor = .clear
            let window = PassthroughWindow(windowScene: scene, hitArea: hitArea)
            window.rootViewController = host
            window.windowLevel = .normal + 1
            window.isHidden = false
            overlay = window
        }
    }
}

/// Where the toasts on screen are, in window coordinates, by toast.
@MainActor
private final class HitArea {
    var frames: [Toast.ID: CGRect] = [:]
}

private final class PassthroughWindow: UIWindow {
    private let hitArea: HitArea

    init(windowScene: UIWindowScene, hitArea: HitArea) {
        self.hitArea = hitArea
        super.init(windowScene: windowScene)
    }

    required init?(coder: NSCoder) { fatalError("Not used from a storyboard") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard hitArea.frames.values.contains(where: { $0.contains(point) }) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// The newest toast, above the bottom toolbar. Older ones wait their turn behind it, and swiping one down puts it away.
private struct ToastStackView: View {
    let center: ToastCenter
    let hitArea: HitArea

    var body: some View {
        ZStack(alignment: .bottom) {
            if let toast = center.toasts.last {
                ToastCard(toast: toast) { center.dismiss(toast.id) }
                    .id(toast.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { hitArea.frames[toast.id] = $0 }
                    .onDisappear { hitArea.frames[toast.id] = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 62)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: center.toasts.last?.id)
    }
}

private struct ToastCard: View {
    let toast: Toast
    let dismiss: () -> Void
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.phone(15, .medium))
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText(countsDown: true))
                if let detail = toast.detail {
                    Text(detail).font(.phone(13)).foregroundStyle(Color.textMuted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = toast.action {
                Button {
                    action.perform()
                    dismiss()
                } label: {
                    Text(action.title)
                        .font(.phone(15, .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Color.selected, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.action == nil ? 16 : 10)
        .frame(minHeight: 56)
        // Solid, not glass: a toast is read in a glance, over whatever the list has under it.
        .background(Color.raised, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.lineStrong))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .offset(y: max(0, drag))
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in if value.translation.height > 24 || value.predictedEndTranslation.height > 80 { dismiss() } }
        )
        .animation(.spring(duration: 0.3), value: toast.title)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: toast.action?.title ?? "Dismiss") {
            toast.action?.perform()
            dismiss()
        }
    }

    private var iconColor: Color {
        switch toast.tone {
        case .neutral: .textSecondary
        case .success: .success
        case .failure: .danger
        }
    }
}
