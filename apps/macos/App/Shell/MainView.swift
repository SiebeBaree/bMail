import DesignSystem
import SwiftUI

/// Layout C: the account switcher and search on top, views as tabs, the list and the open conversation side by side.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("listWidth") private var listWidth = 400.0

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            Hairline()
            HStack(spacing: 0) {
                ConversationList()
                    .frame(width: listWidth)
                ColumnDivider(width: $listWidth, range: 300...600)
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

/// The line between the list and the reader. Drag it to resize the list; the width is remembered.
private struct ColumnDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var startWidth: Double?

    var body: some View {
        Hairline(.vertical)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(.rect)
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = startWidth ?? width
                                startWidth = start
                                width = min(max(start + drag.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            }
            .zIndex(1)
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
