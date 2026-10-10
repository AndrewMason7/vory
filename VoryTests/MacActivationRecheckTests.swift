#if os(macOS)
import Foundation
import Testing
@testable import Vory

/// The Mac re-reads the Companion's version when it comes to the front, a few minutes apart at
/// most (#243): switching apps all day must not re-read it every time.
@Suite struct MacActivationRecheckTests {
    @MainActor @Test func theFirstLookIsDueAndTheNextWaitsForTheGap() {
        let r = ActivationRecheck(minimumGap: 180)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(r.isDue(at: t0))
        r.noteRun(at: t0)
        #expect(!r.isDue(at: t0.addingTimeInterval(10)))
        #expect(!r.isDue(at: t0.addingTimeInterval(179)))
        #expect(r.isDue(at: t0.addingTimeInterval(180)))
    }

    @MainActor @Test func runIfDueRunsOnceWithinTheGap() async {
        let r = ActivationRecheck(minimumGap: 180)
        let t0 = Date(timeIntervalSinceReferenceDate: 2_000)
        final class Count: @unchecked Sendable { var n = 0 }
        let count = Count()
        r.runIfDue(at: t0) { count.n += 1 }
        r.runIfDue(at: t0.addingTimeInterval(5)) { count.n += 1 }
        r.runIfDue(at: t0.addingTimeInterval(200)) { count.n += 1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(count.n == 2)
        #expect(r.lastRun == t0.addingTimeInterval(200))
    }

    @MainActor @Test func launchCountsAsTheFirstLook() {
        let r = ActivationRecheck(minimumGap: 180)
        let launch = Date(timeIntervalSinceReferenceDate: 3_000)
        r.noteRun(at: launch)
        // Coming to the front right after launch (the first click) takes no second look.
        #expect(!r.isDue(at: launch.addingTimeInterval(2)))
    }
}
#endif
