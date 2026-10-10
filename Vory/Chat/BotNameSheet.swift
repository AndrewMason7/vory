import SwiftUI
import VoryCore

/// Edits a bot's display name and title as Vory keeps them (#315): two fields with the gateway's
/// own values (or the folder name) as placeholders, so clearing a field goes back to them. The
/// folder name never changes here. Return saves, Escape cancels; the name field has the focus
/// as the sheet opens, like the chat's rename sheet.
struct BotNameSheet: View {
    var profileName: String
    var gatewayName: String?
    var gatewayTitle: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var title = ""
    @FocusState private var focused: Field?
    private enum Field { case name, title }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Name and title").font(.headline)
            TextField(gatewayName?.isEmpty == false ? gatewayName! : profileName, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .name)
                .onSubmit(save)
                .accessibilityLabel("Display name")
                .accessibilityIdentifier("botName.name")
            TextField(gatewayTitle?.isEmpty == false ? gatewayTitle! : "Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused, equals: .title)
                .onSubmit(save)
                .accessibilityLabel("Title")
                .accessibilityIdentifier("botName.title")
            Text("Shown everywhere this bot appears, on every device. Leave a field empty to use \(gatewayName?.isEmpty == false || gatewayTitle?.isEmpty == false ? "the gateway's" : "the folder name") instead. The folder name, \(profileName), stays as it is.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("botName.save")
            }
        }
        .padding(20)
        .frame(minWidth: 340)
        .onAppear {
            let own = BotNames.names(for: profileName)
            name = own?.displayName ?? ""
            title = own?.title ?? ""
            focused = .name
        }
        #if os(iOS)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { n in
            (n.object as? UITextField)?.selectAll(nil)
        }
        #endif
    }

    private func save() {
        BotNames.set(displayName: name, title: title, for: profileName)
        dismiss()
    }
}
