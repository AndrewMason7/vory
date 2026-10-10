import SwiftUI
import VoryCore

/// The Chats tab on iOS: the chat list and the open chat as the two columns of a split view.
/// On a wide window (iPad, the open iPhone Duo) they stand side by side, like Mail; on a
/// narrow one (any phone, the closed Duo, a narrow iPad window) the split view collapses to
/// one column and the chat is pushed over the list, as it always was. One view serves both,
/// never two roots switched by size class: that would throw the open chat away on every fold.
///
/// The detail path lives in `AppModel.chatPath`, so collapsing and expanding keep the open
/// chat, and `ChatNavigation` (shared with the Mac) decides what selecting a row does to it.
struct ChatsSplitPage: View {
    @Environment(AppModel.self) private var model
    @State private var columns = NavigationSplitViewVisibility.doubleColumn

    /// The model's path as a binding: the list selects into it, the detail stack shows it.
    private var chatPath: Binding<NavigationPath> {
        Binding(get: { model.chatPath }, set: { model.chatPath = $0 })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ChatListView(detailPath: chatPath)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
        } detail: {
            ChatDetailStack(path: chatPath) { NoChatPlaceholder() }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// The detail column before a chat is chosen (a wide window only; collapsed, the list is in front).
struct NoChatPlaceholder: View {
    private static let vory = BotLookSpec(shape: "cloud", eyes: "classic", hex: "#3B7BFF", finish: "flat")

    var body: some View {
        VStack(spacing: 12) {
            BotFaceView(spec: Self.vory, size: 72, mood: BotFaceView.Mood(profile: "vory-empty-detail", state: .idle))
            Text("No chat selected").font(.title3.weight(.semibold))
            Text("Pick one from the list, or start a new one.").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chats.noChat")
    }
}
