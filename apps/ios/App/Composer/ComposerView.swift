import DesignSystem
import MailCore
import MailUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Writing a message, as a full-height sheet. Cc, Bcc and From stay folded until you need them, the quoted message
/// stays folded under what you write, and closing asks first when there's something to lose.
struct ComposerView: View {
    @Bindable var model: ComposerModel
    @Environment(\.fontResolutionContext) private var fontContext
    @FocusState private var focus: Field?
    @State private var recipientFocus: ComposerModel.RecipientKind?
    @State private var isConfirmingDiscard = false
    @State private var isPickingPhotos = false
    @State private var isImportingFiles = false
    @State private var photos: [PhotosPickerItem] = []

    enum Field: Hashable { case subject, body }

    var body: some View {
        @Bindable var text = model.text
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // At the top, where it's seen: the keyboard covers the bottom of the sheet.
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.phone(15))
                            .foregroundStyle(Color.danger)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) { Hairline() }
                            .transition(.opacity)
                    }
                    RecipientField(label: "To", kind: .to, model: model, focused: $recipientFocus) {
                        recipientFocus = nil
                        focus = needsSubject ? .subject : .body
                    }
                    if model.showsCopies {
                        RecipientField(label: "Cc", kind: .cc, model: model, focused: $recipientFocus) { recipientFocus = .bcc }
                        RecipientField(label: "Bcc", kind: .bcc, model: model, focused: $recipientFocus) {
                            recipientFocus = nil
                            focus = needsSubject ? .subject : .body
                        }
                        fromRow
                    } else {
                        foldedRow
                    }
                    subjectRow
                    if model.trackingEnabled { trackingNote }
                    TextEditor(text: $text.editorText, selection: $text.selection)
                        .font(.phone(16))
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .focused($focus, equals: .body)
                        // A hardware keyboard's Tab accepts the suggestion, like on the Mac.
                        .onKeyPress(.tab) { model.text.accept() ? .handled : .ignored }
                        .frame(minHeight: 220, alignment: .topLeading)
                        .padding(.horizontal, 11)
                        .padding(.top, 6)
                    if let quote = model.quoted {
                        QuoteToggle(quote: quote, isShown: $model.showsQuote)
                    }
                    if !model.attachments.isEmpty { attachmentRow }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.canvas)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.hasContent)
        .confirmationDialog("Discard this message?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { model.close() }
            Button("Keep Writing", role: .cancel) {}
        }
        .photosPicker(isPresented: $isPickingPhotos, selection: $photos, matching: .any(of: [.images, .videos]), photoLibrary: .shared())
        .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { model.attach(urls) }
        }
        .onChange(of: photos) { _, items in attach(items) }
        .onChange(of: focus) { _, focus in if focus != .body { model.text.dismissSuggestion() } }
        .animation(.snappy(duration: 0.25), value: model.error)
        .onAppear {
            if model.to.isEmpty { recipientFocus = .to } else { focus = .body }
        }
    }

    private var needsSubject: Bool {
        model.mode == .new || model.mode == .response(.forward)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                if model.hasContent { isConfirmingDiscard = true } else { model.close() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                if !model.send(fontContext: fontContext) { Haptics.failure() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.glassProminent)
            .tint(Color.accent)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        ToolbarItemGroup(placement: .keyboard) {
            extras
            if model.text.suggestion != nil {
                Button {
                    model.text.accept()
                    Haptics.tap()
                } label: {
                    Label("Accept", systemImage: "arrow.right.to.line")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("Accept suggestion")
            }
        }
        ToolbarItemGroup(placement: .bottomBar) { extras }
    }

    /// Attachments and tracking, above the keyboard while typing and along the bottom otherwise.
    @ViewBuilder private var extras: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
            Button("Files", systemImage: "folder") { isImportingFiles = true }
        } label: {
            Image(systemName: "paperclip")
        }
        .accessibilityLabel("Attach")
        Button {
            model.toggleTracking()
        } label: {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(model.trackingEnabled ? Color.accent : Color.textPrimary)
        }
        .accessibilityLabel(model.trackingEnabled ? "Stop tracking opens and clicks" : "Track opens and clicks")
        Spacer()
    }

    private var canSend: Bool {
        !(model.to + model.cc + model.bcc).isEmpty || model.pending.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Cc, Bcc and From in one line until tapped, the way Mail does it.
    private var foldedRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { model.showsCopies = true }
            recipientFocus = .cc
        } label: {
            HStack(spacing: 8) {
                Text("Cc/Bcc, From:").foregroundStyle(Color.textMuted)
                Text(model.account?.address ?? "Choose an account").foregroundStyle(Color.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.phone(16))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var fromRow: some View {
        HStack(spacing: 8) {
            Text("From").font(.phone(16)).foregroundStyle(Color.textMuted)
            Menu {
                Picker("From", selection: $model.accountID) {
                    ForEach(model.accounts) { account in
                        Text(account.address).tag(Account.ID?.some(account.id))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.account?.address ?? "Choose an account").lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.phone(16))
                .foregroundStyle(Color.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var subjectRow: some View {
        HStack(spacing: 8) {
            Text("Subject").font(.phone(16)).foregroundStyle(Color.textMuted)
            TextField("", text: $model.subject)
                .font(.phone(16, .medium))
                .focused($focus, equals: .subject)
                .submitLabel(.next)
                .onSubmit { focus = .body }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var trackingNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg").foregroundStyle(Color.accent)
            Text("Tracking opens and clicks. Never counts you.").foregroundStyle(Color.textSecondary)
            Spacer(minLength: 0)
        }
        .font(.phone(14))
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Hairline() }
        .transition(.opacity)
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.attachments) { file in
                    HStack(spacing: 8) {
                        Image(systemName: "doc").foregroundStyle(Color.textMuted)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(file.filename).font(.phone(14, .medium)).lineLimit(1).truncationMode(.middle)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                .font(.phoneMono(11))
                                .foregroundStyle(Color.textMuted)
                        }
                        .frame(maxWidth: 160, alignment: .leading)
                        Button {
                            withAnimation(.snappy) { model.attachments.removeAll { $0.id == file.id } }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Color.textFaint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(file.filename)")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .frame(height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 12)
    }

    /// Photos arrive as data. Anything but JPEG, PNG and GIF becomes a JPEG, since HEIC doesn't open everywhere.
    private func attach(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photos = []
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    model.error = "Couldn't attach a photo."
                    continue
                }
                let type = item.supportedContentTypes.first ?? .jpeg
                if type.conforms(to: .image), ![UTType.jpeg, .png, .gif].contains(type), let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) {
                    model.attach(jpeg, named: "Photo.jpg")
                } else {
                    model.attach(data, named: "\(type.conforms(to: .movie) ? "Video" : "Photo").\(type.preferredFilenameExtension ?? "jpg")")
                }
            }
        }
    }
}

/// The quoted message, folded under what you write.
private struct QuoteToggle: View {
    let quote: Quote
    @Binding var isShown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isShown.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 40, height: 24)
                    .background(Color.selected, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShown ? "Hide quoted message" : "Show quoted message")
            if isShown {
                VStack(alignment: .leading, spacing: 6) {
                    Text(quote.header).foregroundStyle(Color.textMuted)
                    Text(quote.text)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(20)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().fill(Color.lineStrong).frame(width: 2) }
                }
                .font(.phone(14))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
