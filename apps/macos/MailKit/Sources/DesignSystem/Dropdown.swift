import AppKit
import SwiftUI

extension View {
    /// Opens our own dropdown under this view instead of the system menu. It closes on a click outside, on Esc and when
    /// the app goes to the background; an item closes it by setting `isPresented` to false.
    ///
    /// The content lives in a borderless child window so it can hang below the toolbar, which means it doesn't inherit
    /// this view's environment. Pass it values and closures, never let it read `@Environment` objects.
    public func dropdown<Content: View>(
        isPresented: Binding<Bool>,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(DropdownAnchor(isPresented: isPresented, alignment: alignment, content: content))
    }
}

/// One row in a dropdown: full width, highlighted on hover.
public struct DropdownItemStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(isHovered || configuration.isPressed ? Color.selected : .clear, in: .rect(cornerRadius: Metrics.controlRadius - 2))
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == DropdownItemStyle {
    public static var dropdownItem: DropdownItemStyle { DropdownItemStyle() }
}

private struct DropdownAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let alignment: HorizontalAlignment
    let content: () -> Content

    func makeCoordinator() -> DropdownController { DropdownController() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let controller = context.coordinator
        controller.dismiss = { isPresented = false }
        guard isPresented else { return controller.close() }
        let surface = VStack(alignment: .leading, spacing: 0) { content() }
            .padding(4)
            .frame(minWidth: 220, alignment: .leading)
            .fixedSize()
            .background(Color.raised, in: .rect(cornerRadius: Metrics.popoverRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.popoverRadius).strokeBorder(Color.lineStrong))
            .font(.ui)
            .foregroundStyle(Color.textPrimary)
            .tint(.accent)
        // The next run loop turn, so the anchor has its final frame after a layout pass.
        DispatchQueue.main.async { controller.show(AnyView(surface), below: view, alignment: alignment) }
    }

    static func dismantleNSView(_ view: NSView, coordinator: DropdownController) {
        coordinator.close()
    }
}

@MainActor
final class DropdownController {
    var dismiss: () -> Void = {}
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    func show(_ root: AnyView, below anchor: NSView, alignment: HorizontalAlignment) {
        guard let window = anchor.window else { return }
        let panel = panel ?? makePanel()
        let host = panel.contentView as? FirstClickHostingView ?? FirstClickHostingView(rootView: root)
        host.rootView = root
        panel.contentView = host
        panel.appearance = window.effectiveAppearance

        let size = host.fittingSize
        let anchorFrame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let x = alignment == .trailing ? anchorFrame.maxX - size.width : anchorFrame.minX
        panel.setFrame(NSRect(x: x, y: anchorFrame.minY - 6 - size.height, width: size.width, height: size.height), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.invalidateShadow()
        self.panel = panel
        watch(anchor)
    }

    func close() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        eventMonitor = nil
        resignObserver = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Never takes focus from the main window, so its toolbar and selection don't dim while the dropdown is open.
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func watch(_ anchor: NSView) {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak anchor] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                self.dismiss()
                return nil
            }
            if event.window === self.panel { return event }
            // A click on the anchor itself is its own toggle; closing here too would open it again right away.
            if let anchor, event.window === anchor.window, anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
                return event
            }
            self.dismiss()
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }
}

/// Rows work on the first click even though the panel never becomes key.
private final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
