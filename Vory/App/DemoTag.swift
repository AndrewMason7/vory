import SwiftUI

/// The small "Demo" tag by the gateway's name while the demo runs (#392).
struct DemoTag: View {
    var body: some View {
        Text("Demo")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.accentColor)
    }
}

/// What a page shows in the demo when it needs a gateway of one's own (#392): the Companion, push setup.
struct DemoNeedsGateway: View {
    let what: String
    var body: some View {
        ContentUnavailableView {
            Label("Connect your gateway", systemImage: "network")
        } description: {
            Text("\(what) come from the Vory Companion on your own Hermes gateway. The demo has none: connect yours in Settings › Gateway.")
        }
    }
}
