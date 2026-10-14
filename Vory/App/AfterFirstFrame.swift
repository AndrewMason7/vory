#if os(iOS)
import UIKit

/// Runs work once the next frames are on screen (a one-shot display link, its second tick), or
/// after half a second whatever happens. For the chats' catch-up after a return (#371): the scene
/// update draws the chat as it was left, and the turn that ended away comes in the next update
/// instead of lengthening that one.
@MainActor final class AfterFirstFrame: NSObject {
    private let work: @MainActor () -> Void
    private var link: CADisplayLink?
    private var ticks = 0
    private var done = false

    static func run(_ work: @escaping @MainActor () -> Void) {
        let after = AfterFirstFrame(work)
        // The link holds its target until it is invalidated.
        after.link = CADisplayLink(target: after, selector: #selector(tick))
        after.link?.add(to: .main, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { after.finish() }
    }

    private init(_ work: @escaping @MainActor () -> Void) { self.work = work }

    @objc private func tick() {
        ticks += 1
        if ticks >= 2 { finish() }
    }

    private func finish() {
        link?.invalidate(); link = nil
        guard !done else { return }
        done = true
        work()
    }
}
#endif
