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
    @Environment(\.windowGeometry) private var windowGeometry
    @Environment(\.wideLayout) private var wide
    @State private var columns = NavigationSplitViewVisibility.doubleColumn

    /// The list's column: 380 pt where the window is wide enough for both columns at that (the
    /// iPad, the open Duo in landscape), narrower on a window like the open Duo in portrait
    /// (669 pt), where a 380 pt list left the split view no room for the chat and it put the
    /// list over the chat as a dimmed overlay instead of beside it.
    private var listWidth: (min: CGFloat, ideal: CGFloat) {
        let w = windowGeometry.bounds.width
        return (280, min(380, max(280, (w * 0.42).rounded(.down))))
    }

    /// The model's path as a binding: the list selects into it, the detail stack shows it.
    private var chatPath: Binding<NavigationPath> {
        Binding(get: { model.chatPath }, set: { model.chatPath = $0 })
    }

    var body: some View {
        if wide {
            NavigationSplitView(columnVisibility: $columns) {
                ChatListView(detailPath: chatPath)
                    .onChange(of: model.chatPath.isEmpty, initial: true) { _, empty in
                        model.chatsPathOpen = !empty; model.tabAtRoot[.chats] = empty
                    }
                    .navigationSplitViewColumnWidth(min: listWidth.min, ideal: listWidth.ideal, max: 480)
            } detail: {
                ChatDetailStack(path: chatPath) { NoChatPlaceholder() }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            // One column (a phone, the closed Duo, the open Duo upright, a narrow window): the
            // list's own stack on the same path. The split view collapsed to one column left
            // its empty detail column (the placeholder, with a back button) in front after a
            // chat's Back, instead of the list. The open chat is `AppModel.chatPath`, the draft
            // `ComposerDrafts` and the cursor and scroll place `ChatViewMemory`, so the switch
            // between the two roots loses nothing the person had.
            NavigationStack(path: chatPath) {
                ChatListView(inModelStack: true)
                    // The bar starts coming back the instant a pop begins (the path empties at
                    // the start of the transition), reported for the list and the bar.
                    .onChange(of: model.chatPath.isEmpty, initial: true) { _, empty in
                        model.chatsPathOpen = !empty; model.tabAtRoot[.chats] = empty
                    }
                    .navigationDestination(for: ChatRoute.self) { route in ConversationView(route: route) }
                    .navigationDestination(for: RoomRoute.self) { r in RoomView(room: r.room, initialText: r.initialText) }
            }
        }
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
