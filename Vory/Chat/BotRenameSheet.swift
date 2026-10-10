import SwiftUI
import VoryCore

/// Rename bot… (#315, part two): the new folder name, what it is saved as, why it cannot be
/// (taken, reserved, the default bot), then the warning with Rename in red, the wait while the
/// gateway moves the folder and brings the bot back, and the result. Reached from the card's
/// Home section and from Edit Bot, only where the gateway has the rename route.
struct BotRenameSheet: View {
    var profileName: String
    /// Called with the new folder name once the gateway and Vory both have it; the caller
    /// closes whatever was showing the old name.
    var onRenamed: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    /// The gateway's active profile: the one whose own process serves Vory's address.
    @State private var connected: String?
    @FocusState private var focused: Bool

    private var rt: GatewayRuntime? { model.runtime }
    private var profiles: [ProfileInfo] { rt?.profiles ?? [] }
    private var label: String { profiles.first { $0.name == profileName }?.label ?? profileName }
    private var clean: String { BotRename.cleaned(name) }
    private var refusal: BotRename.Refusal? {
        guard let rt else { return .offline }
        _ = rt
        return BotRename.refusal(renaming: profileName, to: name, profiles: profiles, connected: connected)
    }
    private var canRename: Bool { refusal == nil && !busy }

    var body: some View {
        NavigationStack {
            SettingsList {
                Section {
                    TextField("New name", text: $name)
                        .focused($focused)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .disabled(busy)
                        .accessibilityIdentifier("botRename.name")
                        .onSubmit { if canRename { confirming = true } }
                    if !name.isEmpty, clean != name { Text("Saved as \(clean)").font(.caption).foregroundStyle(.secondary) }
                    if let r = refusal, r != .empty, !name.isEmpty {
                        Text(r.message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("botRename.refusal")
                    }
                } header: { Text("Folder") } footer: {
                    Text("The bot's folder on the gateway, and its name in chats unless it has one of its own. Lowercase letters, digits, dash and underscore.")
                }
                Section {
                    Label("The bot stops and starts again under the new name. Anything it is running right now stops; chats, memory and settings move with it.", systemImage: "arrow.triangle.2.circlepath")
                    Label("Tasks on the Board stay assigned to \(profileName).", systemImage: "rectangle.3.group")
                    Label("Other bots' instructions that mention \(profileName) are not rewritten.", systemImage: "text.bubble")
                    Label("Cron jobs and scripts that name the profile still say \(profileName).", systemImage: "clock")
                } header: { Text("What changes") }
                if busy {
                    Section { HStack(spacing: 10) { ProgressView(); Text("Renaming… the gateway moves the folder and restarts the bot.") }.font(.footnote) }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("botRename.error") } }
            }
            .navigationTitle("Rename \(label)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Renaming…" : "Rename") { confirming = true }
                        .disabled(!canRename)
                        .accessibilityIdentifier("botRename.rename")
                }
            }
            .alert("Rename \(label) to \(clean)?", isPresented: $confirming) {
                Button("Rename", role: .destructive) { Task { await rename() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The gateway renames the bot's folder and restarts it; anything it is running stops. Board tasks, other bots' instructions and cron jobs that say \(profileName) are not changed.")
            }
            .task {
                focused = true
                if let rt, let a: ActiveProfileResponse = try? await rt.api.get("/api/profiles/active") { connected = a.current ?? a.active }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private func rename() async {
        guard let rt else { return }
        busy = true; defer { busy = false }
        error = nil
        do {
            let final = try await BotRename.rename(profileName, to: name, on: rt)
            onRenamed(final)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
