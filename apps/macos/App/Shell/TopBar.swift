import DesignSystem
import MailCore
import SQLiteData
import SwiftUI

/// The top bar lives in the window's own toolbar, so the traffic lights sit centered beside it and empty space drags
/// the window. Shared glass backgrounds are hidden: these are our controls, styled our way.
struct TopBar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 12) {
                Logo()
                Text("/").font(.geist(18, .light)).foregroundStyle(Color.lineStrong)
                AccountSwitcher()
            }
            .padding(.leading, 6)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItem(placement: .primaryAction) {
            TrailingControls()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

private struct TrailingControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            SearchField()
            Button {
                model.perform(.compose)
            } label: {
                HStack(spacing: 8) {
                    Text("Compose")
                    KeyCap("C")
                }
            }
            .buttonStyle(.primary)
            AccountMenu()
        }
        .padding(.trailing, 4)
    }
}

private struct Logo: View {
    var body: some View {
        LogoMark(size: 22)
    }
}

/// Like Vercel's team switcher: one click to see every account, ⌘0 to ⌘9 to jump straight to one.
private struct AccountSwitcher: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Account.order(by: \.position)) private var accounts
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 8) {
                AccountMark(current)
                Text(current?.address ?? "All accounts")
                    .font(.uiMedium)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(isOpen ? Color.selected : .clear, in: .rect(cornerRadius: Metrics.controlRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .dropdown(isPresented: $isOpen) {
            row(nil, key: "⌘0") { model.perform(.allAccounts) }
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                row(account, key: index < 9 ? "⌘\(index + 1)" : nil) { model.perform(.account(index + 1)) }
            }
            Hairline().padding(.vertical, 4)
            Button {
                isOpen = false
                model.openSettings()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                    Text("Add account")
                }
                .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.dropdownItem)
        }
    }

    private func row(_ account: Account?, key: String?, action: @escaping () -> Void) -> some View {
        Button {
            isOpen = false
            action()
        } label: {
            HStack(spacing: 10) {
                AccountMark(account)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account?.address ?? "All accounts")
                    if let account {
                        Text(account.kind.label).font(.geist(11.5)).foregroundStyle(Color.textMuted)
                    }
                }
                Spacer(minLength: 16)
                if account?.id == model.accountFilter {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                }
                if let key { KeyCap(key) }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.dropdownItem)
    }

    private var current: Account? {
        accounts.first { $0.id == model.accountFilter }
    }
}

/// An account's initials, or a stack for all of them together.
private struct AccountMark: View {
    let account: Account?

    init(_ account: Account?) {
        self.account = account
    }

    var body: some View {
        if let account {
            Avatar(account.displayName, size: 20)
        } else {
            Image(systemName: "square.stack")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20, height: 20)
                .background(Color.selected, in: .circle)
        }
    }
}

private struct SearchField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.textMuted)
            TextField("Search mail", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { isFocused = false }
            if model.searchText.isEmpty {
                KeyCap("/")
            } else {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: 280, height: Metrics.controlHeight)
        .background(Color.canvas, in: .rect(cornerRadius: Metrics.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(isFocused ? Color.textMuted : Color.line))
        .onChange(of: model.isSearchFocused) { _, focus in
            if focus { isFocused = true }
        }
        .onChange(of: isFocused) { _, focused in model.isSearchFocused = focused }
    }
}

private struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Account.order(by: \.position)) private var accounts
    @State private var isOpen = false

    var body: some View {
        let update = self.update
        Button { isOpen.toggle() } label: {
            Avatar(accounts.first?.displayName ?? "", size: 26)
                .overlay(alignment: .topTrailing) {
                    if update != nil {
                        UpdateDot(size: 8)
                            .padding(2)
                            .background(Color.chrome, in: .circle)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .dropdown(isPresented: $isOpen, alignment: .trailing) {
            if let update {
                Button {
                    isOpen = false
                    model.updater.restart()
                } label: {
                    HStack(spacing: 8) {
                        UpdateDot(size: 6)
                        Text("Restart to update to \(update)")
                    }
                }
                .buttonStyle(.dropdownItem)
                Hairline().padding(.vertical, 4)
            }
            item("Settings", key: "⌘,") { model.openSettings() }
            item("Keyboard shortcuts", key: "?") { model.perform(.shortcuts) }
        }
    }

    /// The version waiting for a restart. Hidden while you write: restarting would throw the message away.
    private var update: String? {
        model.composer == nil ? model.updater.readyVersion : nil
    }

    private func item(_ title: String, key: String?, action: @escaping () -> Void) -> some View {
        Button {
            isOpen = false
            action()
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 16)
                if let key { KeyCap(key) }
            }
        }
        .buttonStyle(.dropdownItem)
    }
}

/// Blue, like an unread dot: a new version is ready.
private struct UpdateDot: View {
    let size: CGFloat

    var body: some View {
        Circle().fill(Color.link).frame(width: size, height: size)
    }
}
