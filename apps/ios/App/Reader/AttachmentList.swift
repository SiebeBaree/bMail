import DesignSystem
import MailCore
import MailUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// A message's files. Tap one to download it and open it in Quick Look, which can also share and save it.
struct AttachmentList: View {
    let message: Message
    @Environment(AppModel.self) private var model
    @State private var downloading: Set<Attachment.ID> = []
    @State private var preview: URL?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(message.listedAttachments) { file in
                Button { open(file) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            if downloading.contains(file.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: symbol(for: file)).font(.system(size: 17)).foregroundStyle(Color.textSecondary)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .background(Color.selected, in: .rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.filename).font(.phone(15, .medium)).lineLimit(1).truncationMode(.middle)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                .font(.phoneMono(12))
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(downloading.contains(file.id))
                .accessibilityLabel("\(file.filename), \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                .accessibilityHint("Opens the file")
            }
        }
        .padding(.horizontal, 16)
        .quickLookPreview($preview)
    }

    /// Downloads once per launch into the caches folder: the system may clear it, and links and Gmail's ids expire, so
    /// nothing keeps a copy for longer.
    private func open(_ file: Attachment) {
        let folder = URL.cachesDirectory.appending(path: "Attachments/\(file.id.uuidString)", directoryHint: .isDirectory)
        let destination = folder.appending(path: file.filename.isEmpty ? "Attachment" : file.filename)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            preview = destination
            return
        }
        downloading.insert(file.id)
        Task {
            defer { downloading.remove(file.id) }
            do {
                let data = try await model.session.download(file, of: message)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
                preview = destination
            } catch {
                Haptics.failure()
                model.session.toasts.show(Toast("Couldn't open \(file.filename).", detail: error.localizedDescription, symbol: "exclamationmark.triangle", tone: .failure))
            }
        }
    }

    private func symbol(for file: Attachment) -> String {
        guard let type = UTType(mimeType: file.contentType) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        return "doc"
    }
}
