import DesignSystem
import MailCore
import Providers
import SQLiteData
import SwiftUI

struct DomainSettings: View {
    @Environment(AppModel.self) private var model
    @FetchAll(Domain.order(by: \.name)) private var domains
    @FetchAll(Account.where { $0.kind.eq(Account.Kind.domain) }.order(by: \.address)) private var mailboxes
    @State private var newDomain = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text("Domains").font(.pageTitle)
                Spacer()
                TextField("example.com", text: $newDomain)
                    .textFieldStyle(.field)
                    .frame(width: 220)
                    .onSubmit(addDomain)
                Button("Add domain", action: addDomain)
                    .buttonStyle(.secondary)
                    .disabled(newDomain.isEmpty)
            }
            if let error { Text(error).foregroundStyle(Color.danger) }
            if domains.isEmpty {
                Text("Add a domain you own to send and receive from it. You'll get the DNS records to add.")
                    .foregroundStyle(Color.textMuted)
            }
            ForEach(domains) { domain in
                DomainSection(domain: domain, mailboxes: mailboxes.filter { $0.domainID == domain.id }, error: $error)
            }
        }
    }

    private func addDomain() {
        let name = newDomain.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                try model.store.merge(try await ServerAdmin(connection: model.server).addDomain(name), source: "settings")
                newDomain = ""
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct DomainSection: View {
    let domain: Domain
    let mailboxes: [Account]
    @Binding var error: String?
    @Environment(AppModel.self) private var model
    @State private var newLocalPart = ""
    @State private var isChecking = false

    private var admin: ServerAdmin { ServerAdmin(connection: model.server) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(domain.name).font(.geist(17, .semibold))
                HStack(spacing: 6) {
                    StatusDot(domain.status == .verified ? .success : domain.status == .failed ? .danger : .warning)
                    Text(domain.status.label).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button(isChecking ? "Checking" : "Check DNS", action: verify)
                    .buttonStyle(.ghost)
                    .disabled(isChecking)
            }
            .padding(.bottom, 12)

            row("Catch-all") {
                Menu {
                    Button("Off") { setCatchAll(nil) }
                    ForEach(mailboxes) { mailbox in Button(mailbox.address) { setCatchAll(mailbox.id) } }
                } label: {
                    HStack(spacing: 8) {
                        Text(mailboxes.first { $0.id == domain.catchAllMailboxID }?.address ?? "Off")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                Text("Gets mail for addresses without a mailbox.").foregroundStyle(Color.textMuted)
            }
            row("Tracking host") {
                Text(domain.trackingHost).font(.meta)
                StatusDot(domain.trackingHostVerified ? .success : .warning)
                Text(domain.trackingHostVerified ? "Verified" : "Until it's live, tracking uses \(model.server.baseURL.host() ?? "the api").")
                    .foregroundStyle(Color.textMuted)
            }

            Text("DNS records").font(.uiSemibold).padding(.top, 24).padding(.bottom, 8)
            RecordTable(records: domain.records)

            Text("Mailboxes").font(.uiSemibold).padding(.top, 24).padding(.bottom, 4)
            ForEach(mailboxes) { mailbox in
                HStack(spacing: 12) {
                    Text(mailbox.address).frame(width: 220, alignment: .leading)
                    Text(mailbox.displayName).foregroundStyle(Color.textSecondary)
                    Spacer()
                    if mailbox.id == domain.catchAllMailboxID { Text("Catch-all").foregroundStyle(Color.textMuted) }
                }
                .frame(height: 40)
                .overlay(alignment: .bottom) { Hairline() }
            }
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    TextField("name", text: $newLocalPart).textFieldStyle(.plain).onSubmit(addMailbox)
                    Text("@\(domain.name)").foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, 10)
                .frame(width: 320, height: Metrics.controlHeight)
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
                Button(action: addMailbox) {
                    HStack(spacing: 8) { Text("Create"); KeyCap("↵") }
                }
                .buttonStyle(.secondary)
                .disabled(newLocalPart.isEmpty)
            }
            .padding(.top, 12)
        }
        .task(id: domain.status) {
            // Pending DNS gets checked every 30 seconds while this screen is open.
            while domain.status == .pending, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { verify() }
            }
        }
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(Color.textSecondary).frame(width: 140, alignment: .leading)
            content()
            Spacer()
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func run(_ operation: @escaping () async throws -> ChangeSet) {
        Task {
            do {
                try model.store.merge(try await operation(), source: "settings")
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func verify() {
        isChecking = true
        Task {
            do { try model.store.merge(try await admin.verifyDomain(domain.id), source: "settings") } catch { self.error = error.localizedDescription }
            isChecking = false
        }
    }

    private func setCatchAll(_ id: Account.ID?) { run { try await admin.setCatchAll(id, for: domain.id) } }

    private func addMailbox() {
        let localPart = newLocalPart.trimmingCharacters(in: .whitespaces).lowercased()
        guard !localPart.isEmpty else { return }
        newLocalPart = ""
        run { try await admin.addMailbox(localPart: localPart, displayName: localPart.capitalized, on: domain.id) }
    }
}

private struct RecordTable: View {
    let records: [DNSRecord]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                ForEach(["Type", "Name", "Value", "Priority", "Status", ""], id: \.self) { Text($0).foregroundStyle(Color.textMuted) }
            }
            .frame(height: 32)
            ForEach(records, id: \.self) { record in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text(record.type)
                    Text(record.name).font(.meta)
                    Text(record.value).font(.meta).lineLimit(1).truncationMode(.middle).frame(maxWidth: 300, alignment: .leading).textSelection(.enabled)
                    Text(record.priority.map(String.init) ?? "").font(.meta)
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

extension Domain.Status {
    var label: String {
        switch self {
        case .pending: "Waiting for DNS"
        case .verified: "Verified"
        case .failed: "DNS check failed"
        }
    }
}

extension DNSRecord.Status {
    var label: String {
        switch self {
        case .pending: "Pending"
        case .verified: "Verified"
        case .failed: "Failed"
        case .optional: "Recommended"
        }
    }

    var color: Color {
        switch self {
        case .verified: .success
        case .pending: .warning
        case .failed: .danger
        case .optional: .textFaint
        }
    }
}
