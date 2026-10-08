import DesignSystem
import SwiftUI

/// Layout C: the account switcher and search on top, views as tabs, the list and the open conversation side by side.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            Hairline()
            HStack(spacing: 0) {
                ConversationList()
                    .frame(width: 400)
                Hairline(.vertical)
                Group {
                    if let composer = model.composer, composer.replacesReader {
                        ComposerView(model: composer)
                    } else if let id = model.selection {
                        ConversationView(conversationID: id)
                            .id(id)
                    } else {
                        EmptyReader()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.canvas)
        .toolbar { TopBar() }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct EmptyReader: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                KeyCap("J")
                KeyCap("K")
                Text("to move").foregroundStyle(Color.textMuted)
            }
            HStack(spacing: 6) {
                KeyCap("C")
                Text("to write").foregroundStyle(Color.textMuted)
            }
        }
        .font(.ui)
    }
}
