import SwiftUI
import VoryCore

/// "All Models…" from a model menu: the chat to choose for, the sheet presented where it can be (`AppModel.modelChooser`).
struct ModelChooserRequest: Identifiable {
    let id = UUID()
    let chat: ChatSession
}

/// Every model the gateway offers, by provider, searchable, with the favourites on top (#401). The model menu lists
/// a provider's featured models; a gateway with many providers (a tester has about a thousand models) needs a search,
/// and the models a person switches between kept to hand.
///
/// A row picks its model; its star keeps it as a favourite (for VoiceOver, "Add to favourites" / "Remove from
/// favourites" on the row). Favourites are reordered by dragging (Edit on the iPhone) and removed by swiping or their
/// star. One the gateway no longer offers stays, marked unavailable, until it is removed. Pulling the list down asks the
/// gateway for its list again.
struct ModelChooserSheet: View {
    @Bindable var chat: ChatSession
    @Environment(\.dismiss) private var dismiss
    @State private var options: ModelOptionsResult?
    @State private var index: [ProviderModels] = []
    @State private var error: String?
    @State private var query = ""
    @State private var favourites = FavouriteModels.shared
    /// When the sheet was made, for the perf log's "ready in" (DEBUG).
    @State private var madeAt = DispatchTime.now()

    /// A provider's models with their lowercased names, made once per list: a search runs on every keystroke.
    struct ProviderModels: Identifiable {
        struct Entry { var name: String; var lower: String }
        var slug: String
        var name: String
        var nameLower: String
        var models: [Entry]
        var id: String { slug }
    }

    private var gateway: UUID { chat.runtime.connection.id }

    var body: some View {
        NavigationStack {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            let favs = favourites.list(gateway).filter { q.isEmpty || matches($0, q) }
            let groups = filtered(q)
            List {
                if !favs.isEmpty {
                    Section("Favourites") {
                        ForEach(favs) { f in row(f, inFavourites: true) }
                            // Reordered in the whole list only: a search shows some of them.
                            .onMove(perform: q.isEmpty ? { favourites.move(gateway, from: $0, to: $1) } : nil)
                            .onDelete { idx in for i in idx { favourites.remove(favs[i], gateway) } }
                    }
                }
                if options != nil {
                    ForEach(groups) { p in
                        Section(p.name) {
                            ForEach(p.models, id: \.name) { m in row(FavouriteModel(provider: p.slug, model: m.name), inFavourites: false) }
                        }
                    }
                    if !q.isEmpty, favs.isEmpty, groups.isEmpty {
                        Text("No model matches “\(query)”").foregroundStyle(.secondary)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .searchable(text: $query, prompt: "Search models")
            // Asks the gateway to look again (a key added, a model dropped since the list was fetched).
            .refreshable { await load(refresh: true) }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("models.done") }
                #if os(iOS)
                if !favourites.list(gateway).isEmpty { ToolbarItem(placement: .topBarLeading) { EditButton() } }
                #endif
            }
            .accessibilityIdentifier("models.sheet")
        }
        .task { await load(refresh: false) }
        .onAppear { Perf.stamp("models: list appeared, \(Self.ms(since: madeAt)) ms after it was made") }
        // How long a keystroke takes to be drawn: the filter and the list's update, to the next turn of the main loop.
        .onChange(of: query) { _, q in
            let t = DispatchTime.now()
            DispatchQueue.main.async { Perf.note("models: search '\(q)' drawn in \(Self.ms(since: t)) ms") }
        }
    }

    private static func ms(since t: DispatchTime) -> Int { Int((DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1_000_000) }

    private func matches(_ f: FavouriteModel, _ q: String) -> Bool {
        f.model.lowercased().contains(q) || (options?.providerName(f.provider) ?? f.provider).lowercased().contains(q)
    }

    /// The providers with the models that match, a provider whose name matches with all of its models.
    private func filtered(_ q: String) -> [ProviderModels] {
        guard !q.isEmpty else { return index }
        return index.compactMap { p in
            if p.nameLower.contains(q) { return p }
            let hits = p.models.filter { $0.lower.contains(q) }
            return hits.isEmpty ? nil : ProviderModels(slug: p.slug, name: p.name, nameLower: p.nameLower, models: hits)
        }
    }

    @ViewBuilder private func row(_ f: FavouriteModel, inFavourites: Bool) -> some View {
        let isFav = favourites.contains(f, gateway)
        // A provider's own rows are what it offers; only a favourite can be one it no longer does.
        let offered = inFavourites ? (options?.offers(f) ?? true) : true
        let current = chat.modelName == f.model && (chat.providerSlug ?? f.provider) == f.provider
        let provider = options?.providerName(f.provider) ?? f.provider
        HStack(spacing: 10) {
            Button { pick(f) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.model).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(offered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    if inFavourites {
                        Text(offered ? provider : "\(provider) · unavailable").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!offered)
            if current { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
            Button { withAnimation(.snappy) { favourites.toggle(f, gateway) } } label: {
                Image(systemName: isFav ? "star.fill" : "star").foregroundStyle(isFav ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                    .frame(width: 30, height: 30).contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(isFav ? "Remove from favourites" : "Add to favourites")
            .accessibilityLabel(isFav ? "Remove from favourites" : "Add to favourites")
            .accessibilityIdentifier("models.star.\(f.id)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([f.model, provider, current ? "current" : nil, offered ? nil : "unavailable", isFav ? "favourite" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if offered { pick(f) } }
        .accessibilityAction(named: isFav ? "Remove from favourites" : "Add to favourites") { favourites.toggle(f, gateway) }
        .accessibilityIdentifier(inFavourites ? "models.favrow.\(f.id)" : "models.row.\(f.id)")
    }

    private func pick(_ f: FavouriteModel) {
        Task {
            do { try await chat.setModel(provider: f.provider, model: f.model) }
            catch { chat.banner = error.localizedDescription }
        }
        dismiss()
    }

    private func load(refresh: Bool) async {
        do {
            let o = try await chat.modelOptions(refresh: refresh)
            options = o
            index = o.sortedProviders.map { p in
                let models = p.models ?? p.featuredModels ?? []
                return ProviderModels(slug: p.slug, name: p.name, nameLower: p.name.lowercased(), models: models.map { .init(name: $0, lower: $0.lowercased()) })
            }
            error = nil
            let n = index.reduce(0) { $0 + $1.models.count }
            DispatchQueue.main.async { Perf.note("models: list of \(n) ready in \(Self.ms(since: madeAt)) ms") }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
