import DesignSystem
import MailCore
import MailUI
import Providers
import SQLiteData
import SwiftUI

/// Domains you own, each one set up once: DNS, where unknown addresses go and the tracking host. Addresses on them are
/// added under Accounts.
struct DomainsSection: View {
    var isDomainFieldFocused: FocusState<Bool>.Binding
    @Environment(AppModel.self) private var model
    @FetchAll(Domain.order(by: \.name)) private var domains
    @FetchAll(Account.where { $0.kind.eq(Account.Kind.domain) }.order(by: \.address)) private var mailboxes
    @State private var expanded: Set<Domain.ID> = []
    @State private var newDomain = ""
    @State private var isAdding = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Domains") { EmptyView() }
            if let error {
                Text(error).foregroundStyle(Color.danger).padding(.vertical, 12)
            }
            ForEach(domains) { domain in
                DomainRow(
                    domain: domain,
                    mailboxes: mailboxes.filter { $0.domainID == domain.id },
                    isExpanded: expanded.contains(domain.id),
                    toggle: { toggle(domain.id) },
                    error: $error
                )
            }
            if domains.isEmpty {
                Text("Add a domain you own to send and receive from it. You'll get the DNS records to add at your registrar.")
                    .foregroundStyle(Color.textMuted)
                    .padding(.vertical, 16)
            }
            HStack(spacing: 8) {
                TextField("example.com", text: $newDomain)
                    .textFieldStyle(.field)
                    .frame(width: 260)
                    .focused(isDomainFieldFocused)
                    .onSubmit(addDomain)
                Button(isAdding ? "Adding" : "Add domain", action: addDomain)
                    .buttonStyle(.secondary)
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            .padding(.top, 16)
        }
        // A domain still waiting for DNS starts open, because its records are what you came for.
        .onChange(of: domains.filter { $0.status != .verified }.map(\.id), initial: true) { _, pending in
            expanded.formUnion(pending)
        }
    }

    private func toggle(_ id: Domain.ID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func addDomain() {
        let name = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                let changes = try await model.session.admin.addDomain(name)
                try model.session.store.merge(changes, source: "settings")
                expanded.formUnion(changes.domains.map(\.id))
                newDomain = ""
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct DomainRow: View {
    let domain: Domain
    let mailboxes: [Account]
    let isExpanded: Bool
    let toggle: () -> Void
    @Binding var error: String?
    @Environment(AppModel.self) private var model
    @State private var isChecking = false
    @State private var isCatchAllOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    Text(domain.name).font(.uiMedium)
                    HStack(spacing: 6) {
                        StatusDot(domain.status.color)
                        Text(domain.status.label).foregroundStyle(Color.textSecondary)
                    }
                    .padding(.leading, 6)
                    Spacer()
                    Text(mailboxes.count == 1 ? "1 address" : "\(mailboxes.count) addresses").foregroundStyle(Color.textMuted)
                }
                .frame(height: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("DNS records").font(.uiSemibold)
                        Spacer()
                        Button(isChecking ? "Checking" : "Check DNS", action: verify)
                            .buttonStyle(.secondary)
                            .disabled(isChecking)
                    }
                    .padding(.bottom, 6)
                    RecordTable(records: domain.records)
                        .padding(.bottom, 16)

                    SettingRow("Catch-all", note: "Gets mail sent to addresses that don't exist.") {
                        Button { isCatchAllOpen.toggle() } label: {
                            HStack(spacing: 8) {
                                Text(mailboxes.first { $0.id == domain.catchAllMailboxID }?.address ?? "Off")
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textMuted)
                            }
                        }
                        .buttonStyle(.secondary)
                        .dropdown(isPresented: $isCatchAllOpen, alignment: .trailing) {
                            catchAllOption("Off", id: nil)
                            ForEach(mailboxes) { mailbox in catchAllOption(mailbox.address, id: mailbox.id) }
                        }
                    }
                    SettingRow("Tracking host", note: domain.trackingHostVerified ? "Opens and clicks go through your own domain." : "Until this is live, tracked mail uses \(model.session.server?.baseURL.host() ?? "the api").") {
                        HStack(spacing: 6) {
                            StatusDot(domain.trackingHostVerified ? .success : .warning)
                            Text(domain.trackingHost).font(.meta)
                        }
                    }
                    SettingRow("Remove domain", note: "Deletes every address on it and all their mail.") {
                        ConfirmButton(title: "Remove", confirmation: "Remove \(domain.name) and its mail") { remove() }
                    }
                }
                .padding(.leading, 22)
                .padding(.bottom, 20)
            }
            Hairline()
        }
        .task(id: [domain.status == .pending, domain.trackingHostVerified]) {
            // DNS and the tracking host get checked every 30 seconds while settings are open, until both are live.
            while domain.status == .pending || !domain.trackingHostVerified, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { verify() }
            }
        }
    }

    private func catchAllOption(_ title: String, id: Account.ID?) -> some View {
        Button {
            isCatchAllOpen = false
            run { try await model.session.admin.setCatchAll(id, for: domain.id) }
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 16)
                if domain.catchAllMailboxID == id {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .buttonStyle(.dropdownItem)
    }

    private func run(_ operation: @escaping () async throws -> ChangeSet) {
        Task {
            do {
                try model.session.store.merge(try await operation(), source: "settings")
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func verify() {
        isChecking = true
        Task {
            defer { isChecking = false }
            do { try model.session.store.merge(try await model.session.admin.verifyDomain(domain.id), source: "settings") } catch { self.error = error.localizedDescription }
        }
    }

    private func remove() {
        let removed = mailboxes.map(\.id)
        run {
            var changes = try await model.session.admin.removeDomain(domain.id)
            changes.removedAccountIDs = removed
            return changes
        }
    }
}

private struct RecordTable: View {
    let records: [DNSRecord]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                ForEach(["Type", "Name", "Value", "Status", ""], id: \.self) { Text($0).foregroundStyle(Color.textMuted) }
            }
            .frame(height: 30)
            ForEach(records, id: \.self) { record in
                Hairline().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text(record.type)
                    Text(record.name).font(.meta)
                    Text(record.priority.map { "\($0) \(record.value)" } ?? record.value)
                        .font(.meta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .help(record.value)
                    HStack(spacing: 6) {
                        StatusDot(record.status.color)
                        Text(record.status.label).foregroundStyle(Color.textSecondary)
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.value, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(.ghost)
                    .help("Copy value")
                }
                .frame(height: 38)
            }
        }
        .font(.geist(12.5))
    }
}
