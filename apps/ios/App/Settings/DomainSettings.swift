import DesignSystem
import MailCore
import MailUI
import SQLiteData
import SwiftUI

/// One domain, set up once: the DNS records to add at your registrar, where unknown addresses go and the tracking host.
/// While anything is still waiting for DNS, it's checked again every 30 seconds.
struct DomainSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FetchOne private var domain: Domain?
    @FetchAll private var mailboxes: [Account]
    @State private var isChecking = false
    @State private var isConfirmingRemoval = false

    init(domainID: Domain.ID) {
        _domain = FetchOne(wrappedValue: nil, Domain.find(domainID))
        _mailboxes = FetchAll(Account.where { $0.domainID.eq(domainID) }.order(by: \.address))
    }

    var body: some View {
        List {
            if let domain {
                Section {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            StatusDot(domain.status.color)
                            Text(domain.status.label)
                        }
                    }
                    Button(isChecking ? "Checking DNS" : "Check DNS Now", action: verify)
                        .disabled(isChecking)
                }
                .listRowBackground(Color.raised)

                Section {
                    ForEach(domain.records, id: \.self) { record in
                        RecordRow(record: record) { copy(record.value, "Value") }
                            .contextMenu {
                                Button("Copy Name", systemImage: "doc.on.doc") { copy(record.name, "Name") }
                                Button("Copy Value", systemImage: "doc.on.doc") { copy(record.value, "Value") }
                            }
                    }
                } header: {
                    Text("DNS records")
                } footer: {
                    Text("Add these at your registrar. Tap one to copy its value.")
                }
                .listRowBackground(Color.raised)

                Section {
                    Picker("Catch-all", selection: Binding { domain.catchAllMailboxID } set: { setCatchAll($0) }) {
                        Text("Off").tag(Account.ID?.none)
                        ForEach(mailboxes) { mailbox in
                            Text(mailbox.address).tag(Account.ID?.some(mailbox.id))
                        }
                    }
                    LabeledContent("Tracking host") {
                        HStack(spacing: 6) {
                            StatusDot(domain.trackingHostVerified ? .success : .warning)
                            Text(domain.trackingHost).font(.phoneMono(14))
                        }
                    }
                } footer: {
                    Text(domain.trackingHostVerified
                        ? "Mail to addresses that don't exist goes to the catch-all. Opens and clicks go through your own domain."
                        : "Mail to addresses that don't exist goes to the catch-all. Until the tracking host is live, tracked mail uses \(model.session.server?.baseURL.host() ?? "your server").")
                }
                .listRowBackground(Color.raised)

                Section {
                    Button("Remove Domain", role: .destructive) { isConfirmingRemoval = true }
                        .foregroundStyle(Color.danger)
                } footer: {
                    Text(mailboxes.count == 1 ? "Deletes its 1 address and all its mail." : "Deletes its \(mailboxes.count) addresses and all their mail.")
                }
                .listRowBackground(Color.raised)
            }
        }
        .font(.phone(16))
        .scrollContentBackground(.hidden)
        .background(Color.chrome)
        .navigationTitle(domain?.name ?? "Domain")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(domain?.name ?? "this domain")?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("Every address on it stops receiving mail, and their mail is deleted. This can't be undone.")
        }
        .task(id: [domain?.status == .pending, domain?.trackingHostVerified == false]) {
            while let domain, domain.status == .pending || !domain.trackingHostVerified, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { verify() }
            }
        }
    }

    private func copy(_ text: String, _ what: String) {
        UIPasteboard.general.string = text
        Haptics.tap()
        model.session.toasts.show(Toast("\(what) copied", symbol: "doc.on.doc", duration: .seconds(2)))
    }

    private func verify() {
        guard let domain, !isChecking else { return }
        isChecking = true
        run("Couldn't check DNS.") {
            defer { isChecking = false }
            return try await model.session.admin.verifyDomain(domain.id)
        }
    }

    private func setCatchAll(_ mailbox: Account.ID?) {
        guard let domain else { return }
        run("Couldn't change the catch-all.") { try await model.session.admin.setCatchAll(mailbox, for: domain.id) }
    }

    private func remove() {
        guard let domain else { return }
        let removed = mailboxes.map(\.id)
        dismiss()
        run("Couldn't remove \(domain.name).") {
            var changes = try await model.session.admin.removeDomain(domain.id)
            changes.removedAccountIDs = removed
            return changes
        }
    }

    private func run(_ failure: String, _ operation: @escaping () async throws -> ChangeSet) {
        Task {
            do {
                try model.session.store.merge(try await operation(), source: "settings")
            } catch {
                Haptics.failure()
                model.session.toasts.show(Toast(failure, detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
    }
}

/// One record: what kind, where it goes and what it says, with whether DNS has it yet.
private struct RecordRow: View {
    let record: DNSRecord
    let copy: () -> Void

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.type).font(.phoneMono(13)).foregroundStyle(Color.textSecondary)
                    Text(record.name).font(.phoneMono(13)).foregroundStyle(Color.textPrimary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    StatusDot(record.status.color)
                    Text(record.status.label).font(.phone(13)).foregroundStyle(Color.textMuted)
                }
                Text(record.priority.map { "\($0) \(record.value)" } ?? record.value)
                    .font(.phoneMono(12))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Copies the value")
    }
}
