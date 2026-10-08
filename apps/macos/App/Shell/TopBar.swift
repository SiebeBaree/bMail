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
        Image(systemName: "envelope")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.onInverted)
            .frame(width: 22, height: 22)
            .background(Color.inverted, in: .rect(cornerRadius: 6))
            .accessibilityLabel("Baree Mail")
    }
}

/// Like Vercel's team switcher: one click to see every account, numbers to jump straight to one.
private struct AccountSwitcher: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Account.order(by: \.position)) private var accounts

    var body: some View {
        Menu {
            Button {
                model.perform(.allAccounts)
            } label: {
                Text("All accounts")
            }
            .keyboardShortcut("0")
            Divider()
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                Button(account.address) { model.perform(.account(index + 1)) }
                    .keyboardShortcut(KeyEquivalent(Character(String(min(index + 1, 9)))))
            }
            Divider()
            Button("Add account…") { model.openSettings() }
        } label: {
            HStack(spacing: 8) {
                if let current {
                    Avatar(current.displayName, size: 20)
                } else {
                    Image(systemName: "square.stack")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Color.selected, in: .circle)
                }
                Text(current?.address ?? "All accounts")
                    .font(.uiMedium)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var current: Account? {
        accounts.first { $0.id == model.accountFilter }
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

    var body: some View {
        Menu {
            Button("Settings…") { model.openSettings() }
                .keyboardShortcut(",")
            Button("Keyboard shortcuts") { model.perform(.shortcuts) }
            Divider()
            Button("Sign out") { Task { await model.signOut() } }
        } label: {
            Avatar("Siebe Baree", size: 26)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
