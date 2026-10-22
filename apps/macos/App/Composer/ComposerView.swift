import DesignSystem
import MailCore
import MailUI
import SwiftUI

struct ComposerView: View {
    @Bindable var model: ComposerModel
    @Environment(\.fontResolutionContext) private var fontContext
    @FocusState private var focus: Field?
    @State private var isFromOpen = false

    enum Field { case subject, body }

    var body: some View {
        @Bindable var text = model.text
        VStack(spacing: 0) {
            if model.replacesReader {
                HStack(spacing: 8) {
                    Text(model.title).font(.uiSemibold)
                    if let draft = model.draft {
                        Text("Written by \(draft.agent)").foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    Text("Discard").foregroundStyle(Color.textMuted)
                    KeyCap("Esc")
                }
                .padding(.horizontal, 20)
                .frame(height: 48)
                .overlay(alignment: .bottom) { Hairline() }
            }
            fromRow
            RecipientField(label: "To", addresses: $model.to, focusOnAppear: model.to.isEmpty)
            if model.showsCopies {
                RecipientField(label: "Cc", addresses: $model.cc)
                RecipientField(label: "Bcc", addresses: $model.bcc)
            }
            if model.mode == .new || model.mode == .forward || model.draft != nil {
                HStack(spacing: 12) {
                    Text("Subject").foregroundStyle(Color.textMuted).frame(width: 56, alignment: .leading)
                    TextField("", text: $model.subject)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .subject)
                        .onSubmit { focus = .body }
                }
                .padding(.horizontal, 20)
                .frame(height: 44)
                .overlay(alignment: .bottom) { Hairline() }
            }
            TextEditor(text: $text.editorText, selection: $text.selection)
                .font(.reading)
                .scrollContentBackground(.hidden)
                .scrollDisabled(!model.replacesReader)
                .focused($focus, equals: .body)
                .frame(minHeight: model.replacesReader ? 260 : 140, maxHeight: model.replacesReader ? .infinity : nil)
                .padding(.horizontal, 15)
                .padding(.top, 12)
            if let quote = model.quoted {
                QuoteToggle(quote: quote, isShown: $model.showsQuote)
            }
            if !model.attachments.isEmpty {
                attachmentRow
            }
            if let error = model.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Color.danger)
                    Text(error)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(Color.canvas)
        .overlay {
            if !model.replacesReader {
                RoundedRectangle(cornerRadius: Metrics.popoverRadius).strokeBorder(Color.lineStrong)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.attach(urls)
            return true
        }
        .onAppear { if !model.to.isEmpty, model.mode != .forward { focus = .body } }
        .onChange(of: model.to) { _, _ in model.error = nil }
        .onChange(of: focus) { _, focus in if focus != .body { model.text.dismissSuggestion() } }
    }

    private var fromRow: some View {
        HStack(spacing: 12) {
            Text("From").foregroundStyle(Color.textMuted).frame(width: 56, alignment: .leading)
            Button { isFromOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Text(model.account.map { "\($0.displayName) <\($0.address)>" } ?? "Choose an account")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .dropdown(isPresented: $isFromOpen) {
                ForEach(model.accounts) { account in
                    Button {
                        isFromOpen = false
                        model.accountID = account.id
                    } label: {
                        HStack(spacing: 10) {
                            Avatar(account.displayName, size: 20)
                            Text(account.address)
                            Spacer(minLength: 16)
                            if account.id == model.accountID {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.dropdownItem)
                }
            }
            Spacer()
            if !model.showsCopies {
                Button("Cc Bcc") { model.showsCopies = true }
                    .buttonStyle(.ghost)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var attachmentRow: some View {
        HStack(spacing: 8) {
            ForEach(model.attachments) { file in
                HStack(spacing: 6) {
                    Image(systemName: "doc").foregroundStyle(Color.textMuted)
                    Text(file.filename).lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.meta).foregroundStyle(Color.textMuted)
                    Button {
                        model.attachments.removeAll { $0.id == file.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(Color.lineStrong))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { model.chooseFiles() } label: { Image(systemName: "paperclip") }
                .buttonStyle(.ghost)
                .help("Attach files")
            Rectangle().fill(Color.lineStrong).frame(width: 1, height: 18)
            Toggle(isOn: $model.trackingEnabled) {
                Text("Track opens and clicks").foregroundStyle(model.trackingEnabled ? Color.textPrimary : Color.textSecondary)
            }
            .toggleStyle(.mailSwitch)
            KeyCap("⌘⇧T")
            if model.trackingEnabled {
                Text("Adds a hidden image and tracked links. Never counts you here.")
                    .font(.geist(12))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if model.text.suggestion != nil {
                Button { model.text.accept() } label: {
                    HStack(spacing: 8) {
                        Text("Accept")
                        KeyCap("Tab")
                    }
                }
                .buttonStyle(.ghost)
            }
            Button {
                model.send(fontContext: fontContext)
            } label: {
                HStack(spacing: 8) {
                    Text("Send")
                    KeyCap("⌘↵")
                }
            }
            .buttonStyle(.primary)
            .keyboardShortcut(.return, modifiers: .command)
            Button("") { model.toggleTracking() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .hidden()
                .frame(width: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: 56)
        .overlay(alignment: .top) { Hairline() }
    }
}

private struct QuoteToggle: View {
    let quote: Quote
    @Binding var isShown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isShown.toggle() } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 16)
                    .background(Color.selected, in: .rect(cornerRadius: Metrics.keyCapRadius))
            }
            .buttonStyle(.plain)
            .help(isShown ? "Hide quoted text" : "Show quoted text")
            if isShown {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quote.header).foregroundStyle(Color.textMuted)
                    Text(quote.text)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(12)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().fill(Color.lineStrong).frame(width: 2) }
                }
                .font(.geist(13))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


