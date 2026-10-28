import Agents
import AppKit
import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// What agents on this Mac may do with each account, and how to connect one.
struct AgentsSection: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Account.order(by: \.position)) private var accounts

    var body: some View {
        @Bindable var agents = model.agents
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Agents") {
                Toggle(isOn: $agents.isEnabled) { EmptyView() }
                    .toggleStyle(.mailSwitch)
                    .accessibilityLabel("Let agents use bMail")
            }
            if agents.isEnabled {
                if let problem = agents.problem {
                    Text(problem).foregroundStyle(Color.danger).padding(.vertical, 12)
                }
                ForEach(accounts) { AgentAccessRow(account: $0) }
                AgentConnection(token: agents.token, newToken: agents.newToken)
            }
        }
    }
}

struct AgentAccessRow: View {
    let account: Account
    @AppStorage private var access: AgentAccess
    @State private var isOpen = false

    init(account: Account) {
        self.account = account
        _access = AppStorage(wrappedValue: .off, AgentAccess.key(for: account.id))
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(account.displayName, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.address).font(.uiMedium)
                Text(account.kind.label).font(.geist(12)).foregroundStyle(Color.textMuted)
            }
            Spacer()
            Button { isOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(access.title)
                    Image(systemName: "chevron.down").font(.controlIcon).foregroundStyle(Color.textMuted)
                }
            }
            .buttonStyle(.secondary)
            .dropdown(isPresented: $isOpen, alignment: .trailing) { options }
        }
        .frame(height: 56)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private var options: some View {
        ForEach(AgentAccess.allCases, id: \.self) { level in
            Button {
                isOpen = false
                access = level
                // Asked here, where the reason is on screen, instead of when the first message arrives.
                if level == .askToSend { AgentNotifications.requestPermission() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.controlIcon)
                        .opacity(level == access ? 1 : 0)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(level.title)
                        Text(level.detail).font(.geist(11.5)).foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.dropdownItem)
        }
    }
}

/// The line to give an agent, with the token in it. Shown with the token cut short; Copy copies all of it.
struct AgentConnection: View {
    let token: String
    let newToken: () -> Void
    @State private var client = Client.claudeCode
    @State private var isOpen = false
    @State private var copied = false

    enum Client: String, CaseIterable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
        case cursor = "Cursor"

        func setup(token: String) -> String {
            switch self {
            case .claudeCode:
                #"claude mcp add --transport http bmail \#(AgentServer.address) --header "Authorization: Bearer \#(token)""#
            case .codex:
                "[mcp_servers.bmail]\nurl = \"\(AgentServer.address)\"\nhttp_headers = { Authorization = \"Bearer \(token)\" }"
            case .cursor:
                #""bmail": { "url": "\#(AgentServer.address)", "headers": { "Authorization": "Bearer \#(token)" } }"#
            }
        }

        var hint: String {
            switch self {
            case .claudeCode: "Run it in a terminal."
            case .codex: "Add it to ~/.codex/config.toml."
            case .cursor: "Add it under mcpServers in ~/.cursor/mcp.json."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { isOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(client.rawValue)
                        Image(systemName: "chevron.down").font(.controlIcon).foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.secondary)
                .dropdown(isPresented: $isOpen) {
                    ForEach(Client.allCases, id: \.self) { option in
                        Button(option.rawValue) {
                            isOpen = false
                            client = option
                            copied = false
                        }
                        .buttonStyle(.dropdownItem)
                    }
                }
                Text(client.setup(token: "bmail_…\(token.suffix(4))"))
                    .font(.meta)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: Metrics.controlHeight, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(client.setup(token: token), forType: .string)
                    copied = true
                }
                .buttonStyle(.secondary)
            }
            HStack {
                Text(client.hint).foregroundStyle(Color.textMuted)
                Spacer()
                ConfirmButton(title: "New token", confirmation: "Every agent will need the new one") {
                    newToken()
                    copied = false
                }
            }
        }
        .padding(.top, 18)
    }
}
