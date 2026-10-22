import Agents
import AppKit
import MailCore
import UserNotifications

/// A notification for each message an agent wrote at Ask to send, so you can send it from wherever you are. Review
/// brings bMail forward, where the message waits in the composer. While bMail is in front there's no banner: the
/// composer is already on screen.
@MainActor
final class AgentNotifications: NSObject, UNUserNotificationCenterDelegate {
    /// Sends the message with this id, from its Send button.
    var send: (Message.ID) -> Void = { _ in }

    private static let category = "agent-message"

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    // Not from the lock screen: only you approve what goes out.
                    UNNotificationAction(identifier: "send", title: "Send", options: .authenticationRequired),
                    UNNotificationAction(identifier: "review", title: "Review", options: .foreground),
                ],
                intentIdentifiers: []
            ),
        ])
        center.delegate = self
    }

    static func requestPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    func post(_ draft: AgentDraft) {
        let content = UNMutableNotificationContent()
        content.title = "\(draft.agent) wants to send to \((draft.to + draft.cc + draft.bcc).map(\.email).joined(separator: ", "))"
        content.body = "\(draft.subject). \(draft.text.split(whereSeparator: \.isWhitespace).joined(separator: " "))"
        content.categoryIdentifier = Self.category
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: draft.id.uuidString, content: content, trigger: nil))
    }

    func remove(_ id: Message.ID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard let id = UUID(uuidString: response.notification.request.identifier) else { return }
        await MainActor.run {
            if action == "send" { send(id) } else { NSApp.activate() }
        }
    }
}
