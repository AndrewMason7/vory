import SwiftUI

#if DEBUG && os(iOS)
/// DEBUG, for UI tests (#409): what VoiceOver would stop on, read the way it reads the screen. XCUITest's own tree lists
/// what VoiceOver skips (a hidden view, the parts of a row combined into one), so it cannot say what is spoken. This walks
/// the window by the accessibility container protocol as VoiceOver does: a hidden branch is skipped, an element is a stop
/// (its parts are not visited), anything else gives its elements or its subviews. Each stop is "label|x,y,w,h".
///
/// On only with `-vory-ax-oracle`: a 1 pt element ("debug.voiceover") whose value is the walk, taken when it is read.
@MainActor
enum VoiceOverOracle {
    nonisolated static let isOn = ProcessInfo.processInfo.arguments.contains("-vory-ax-oracle")

    static func stops(in window: UIWindow) -> [String] {
        var out: [String] = []
        func visit(_ o: NSObject, depth: Int) {
            guard out.count < 3000, depth < 120 else { return }
            if o.accessibilityElementsHidden { return }
            if let v = o as? UIView, v.isHidden || v.alpha < 0.01 || v is OracleView { return }
            if o.isAccessibilityElement {
                let f = o.accessibilityFrame
                guard f.width > 0, f.height > 0, f.intersects(window.bounds) else { return }
                out.append("\(o.accessibilityLabel ?? "")|\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))")
                return
            }
            if let elements = o.accessibilityElements, !elements.isEmpty {
                for case let e as NSObject in elements { visit(e, depth: depth + 1) }
                return
            }
            let n = o.accessibilityElementCount()
            if n != NSNotFound, n > 0 {
                for i in 0..<n { if let e = o.accessibilityElement(at: i) as? NSObject { visit(e, depth: depth + 1) } }
                return
            }
            if let v = o as? UIView { for s in v.subviews { visit(s, depth: depth + 1) } }
        }
        visit(window, depth: 0)
        return out
    }

    final class OracleView: UIView {
        override var isAccessibilityElement: Bool { get { true } set {} }
        override var accessibilityIdentifier: String? { get { "debug.voiceover" } set {} }
        override var accessibilityLabel: String? { get { "VoiceOver oracle" } set {} }
        override var accessibilityValue: String? {
            get { window.map { VoiceOverOracle.stops(in: $0).joined(separator: "\n") } ?? "" }
            set {}
        }
    }

    struct Probe: UIViewRepresentable {
        func makeUIView(context: Context) -> OracleView { OracleView() }
        func updateUIView(_ v: OracleView, context: Context) {}
    }
}
#endif
