import SwiftUI

// What a page built for the phone needs to sit right on the Mac, in three pieces every page
// can share: the settings container, a sheet's size, and a way to refresh without a pull.
// On the phone each is the plain SwiftUI thing it replaces.

/// A settings page's container: the inset grouped list on the phone; on the Mac the grouped
/// form (System Settings' look: boxed sections, switches, a reading width in the middle of
/// the window).
struct SettingsList<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        #if os(macOS)
        // The form spans the window (so its scroller sits at the window's edge and the bar over
        // it is one piece) and its content keeps to a column in the middle.
        GeometryReader { geo in
            Form { content }
                .formStyle(.grouped)
                // A button in a row is the row (a session, a key, a bot), as on the phone; the Mac's
                // default would draw each as a push button. Explicit styles keep their own.
                .buttonStyle(SettingsRowButtonStyle())
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, max(0, (geo.size.width - SettingsList<EmptyView>.width) / 2), for: .scrollContent)
        }
        #else
        List { content }
        #endif
    }
}

extension SettingsList where Content == EmptyView {
    /// The Mac's settings column.
    static var width: CGFloat { 700 }
}

/// How big a sheet opens on the Mac, where a sheet is as big as its content asks to be and a
/// list asks for nothing.
enum SheetSize {
    /// A form or a list: the usual sheet.
    case form
    /// A few controls (a recorder, a short picker).
    case compact
    /// Something to read (a tool call, a long text, a wizard).
    case wide

    var ideal: CGSize {
        switch self {
        case .form: CGSize(width: 520, height: 600)
        case .compact: CGSize(width: 440, height: 340)
        case .wide: CGSize(width: 720, height: 680)
        }
    }
}

#if os(macOS)
/// A row that is a button: its label as written, the whole row the target, the tint for plain
/// text (what a list row's button has on the phone), red for a destructive one.
struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tint))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.5 : (enabled ? 1 : 0.45))
    }
}

private struct MacSheetFrame: ViewModifier {
    let size: SheetSize
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size.ideal.width * 0.85, idealWidth: size.ideal.width, maxWidth: size.ideal.width * 1.5,
                   minHeight: size.ideal.height * 0.7, idealHeight: size.ideal.height, maxHeight: size.ideal.height * 1.5)
            // Esc closes any sheet, with or without a Cancel button of its own.
            .background {
                Button("") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
            }
    }
}

/// The pull-to-refresh of the phone as a toolbar button (⌘R).
private struct ReloadButton: View {
    let action: @MainActor () async -> Void
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task { await action(); busy = false }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(busy)
        .help("Refresh (⌘R)")
    }
}
#endif

extension View {
    /// Gives a sheet's content its size on the Mac; nothing on the phone, where detents do it.
    @ViewBuilder func sheetFrame(_ size: SheetSize = .form) -> some View {
        #if os(macOS)
        modifier(MacSheetFrame(size: size))
        #else
        self
        #endif
    }

    /// A page that names itself in its content (the settings pages' header card): no title in
    /// the bar. On the Mac an empty title would fall back to the window's name, so the title
    /// is taken out of the toolbar instead.
    @ViewBuilder func untitledPage() -> some View {
        #if os(macOS)
        modifier(MacUntitledPage())
        #else
        navigationTitle("").navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// A row's actions: a swipe on the phone, a right-click menu on the Mac (whose settings
    /// forms do not swipe).
    @ViewBuilder func rowActions<Actions: View>(allowsFullSwipe: Bool = true, @ViewBuilder _ actions: () -> Actions) -> some View {
        #if os(macOS)
        contextMenu { actions() }
        #else
        swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) { actions() }
        #endif
    }

    /// Pull to refresh on the phone (Vory's own, the wheel beside the title: `PullRefresh`); a
    /// Refresh button in the toolbar (⌘R) on the Mac.
    @ViewBuilder func reloadable(_ action: @escaping @MainActor () async -> Void) -> some View {
        #if os(macOS)
        modifier(MacReloadable(action: action))
        #else
        pullRefresh(ownWheel: true, action)
        #endif
    }
}

extension View {
    /// A page's search field: the phone's drawer under the title; on the Mac a field in the
    /// window's toolbar, declared only while the page is on show. The Mac keeps visited pages
    /// mounted, and the window's toolbar takes one search field: a second (a kept page's beside
    /// the shown page's) stopped the app (NSToolbar: "Duplicate items of this type are not
    /// allowed", 2026-10-12).
    @ViewBuilder func pageSearchable(text: Binding<String>, prompt: LocalizedStringKey? = nil, always: Bool = false) -> some View {
        #if os(macOS)
        modifier(MacPageSearchable(text: text, prompt: prompt))
        #else
        searchable(text: text, placement: .navigationBarDrawer(displayMode: always ? .always : .automatic), prompt: prompt.map { Text($0) })
        #endif
    }
}

extension View {
    /// `.toolbar` for a page and the pages pushed on it. On the Mac its items stand in the window's
    /// toolbar only while the page is on show: visited pages stay mounted behind the one in front
    /// (MainSplitView), and their items stood in its bar. On the phone, `.toolbar` as it is.
    func pageToolbar<Items: ToolbarContent>(@ToolbarContentBuilder _ items: () -> Items) -> some View {
        modifier(PageToolbar(items: items()))
    }
}

private struct PageToolbar<Items: ToolbarContent>: ViewModifier {
    @Environment(\.macPageShown) private var shown
    let items: Items
    func body(content: Content) -> some View { content.toolbar { if shown { items } } }
}

extension View {
    /// A page pushed on a page's stack. On the Mac its Back stands in the window's toolbar only
    /// while its page is on show: visited pages stay mounted with what was pushed on them (as the
    /// phone's tabs do), and a hidden page's Back stood over the page in front. Nothing on the
    /// phone, where the morph bar owns Back.
    @ViewBuilder func pushedPage() -> some View {
        #if os(macOS)
        modifier(MacPushedPage())
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct MacPushedPage: ViewModifier {
    @Environment(\.macPageShown) private var shown
    func body(content: Content) -> some View { content.navigationBarBackButtonHidden(!shown) }
}
#endif

#if os(macOS)
/// See `untitledPage`. The title comes out of the toolbar only while the page is on show: the Mac
/// keeps visited pages mounted, and a hidden Home took the title out of every page's bar.
private struct MacUntitledPage: ViewModifier {
    @Environment(\.macPageShown) private var shown
    func body(content: Content) -> some View {
        content.navigationTitle("").toolbar(removing: shown ? .title : nil)
            // Pushed on a hidden page's stack, its Back must not stand over the page on show.
            .navigationBarBackButtonHidden(!shown)
    }
}
#endif

#if os(macOS)
/// The Refresh button (⌘R) only while its page is on show: the Mac keeps visited pages mounted
/// behind the one in front, and a hidden page's button stood in its toolbar and answered ⌘R.
private struct MacReloadable: ViewModifier {
    @Environment(\.macPageShown) private var shown
    var action: @MainActor () async -> Void
    func body(content: Content) -> some View {
        content.toolbar { if shown { ToolbarItem(placement: .automatic) { ReloadButton(action: action) } } }
    }
}

/// See `pageSearchable`. The field hangs off an empty background, so the page itself keeps its
/// identity (and its state) as the field comes and goes with the page.
private struct MacPageSearchable: ViewModifier {
    @Environment(\.macPageShown) private var shown
    var text: Binding<String>
    var prompt: LocalizedStringKey?
    func body(content: Content) -> some View {
        content.background {
            if shown { Color.clear.searchable(text: text, placement: .toolbar, prompt: prompt.map { Text($0) }) }
        }
    }
}
#endif

/// Whether the Mac page a view sits in is the one on show. The Mac keeps visited pages mounted
/// behind the one in front (MainSplitView); a page that is mounted but hidden declares no window
/// toolbar items while this is false, or its items would stand in the bar beside the shown
/// page's. Always true where nothing sets it: the iPhone, sheets, the page on show.
extension EnvironmentValues {
    @Entry var macPageShown: Bool = true
}
