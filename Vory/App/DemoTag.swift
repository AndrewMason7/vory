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
