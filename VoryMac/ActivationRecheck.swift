import Foundation

/// Something the Mac re-reads when it comes to the front, but not on every app switch: the
/// Companion's version on the gateway (#243). The iPhone re-reads it each time it comes
/// forward, which happens a few times an hour; a Mac user switches apps all day, so the Mac
/// takes a fresh look at most once every few minutes. Launch counts as the first look.
@MainActor
final class ActivationRecheck {
    /// The Companion's version: a Companion installed from another device while the Mac app
    /// runs shows up within a few minutes instead of at the next relaunch.
    static let companion = ActivationRecheck(minimumGap: 180)

    let minimumGap: TimeInterval
    private(set) var lastRun: Date?

    init(minimumGap: TimeInterval) { self.minimumGap = minimumGap }

    /// Whether a look is due now: none yet, or the last one is older than the gap.
    func isDue(at now: Date = Date()) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= minimumGap
    }

    /// Records a look taken now (by launch, Settings, or `runIfDue`).
    func noteRun(at now: Date = Date()) { lastRun = now }

    /// Runs `work` when a look is due, and counts it; otherwise nothing.
    func runIfDue(at now: Date = Date(), _ work: @escaping @MainActor () async -> Void) {
        guard isDue(at: now) else { return }
        noteRun(at: now)
        Task { await work() }
    }
}
