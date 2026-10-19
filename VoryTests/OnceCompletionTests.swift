#if os(iOS)
import Foundation
import Testing
@testable import Vory

/// #422: the daily backup task is completed once, whether its time runs out first, its work ends first, or both
/// come at once from different threads.
@Suite struct OnceCompletionTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Bool] = []
        func add(_ v: Bool) { lock.lock(); values.append(v); lock.unlock() }
        var all: [Bool] { lock.lock(); defer { lock.unlock() }; return values }
    }

    @Test func theTimeRunningOutFirstWins() {
        let calls = Calls()
        let once = OnceCompletion { calls.add($0) }
        #expect(once.finish(success: false))
        #expect(!once.finish(success: true))
        #expect(calls.all == [false])
    }

    @Test func theWorkEndingFirstWins() {
        let calls = Calls()
        let once = OnceCompletion { calls.add($0) }
        #expect(once.finish(success: true))
        #expect(!once.finish(success: false))
        #expect(calls.all == [true])
    }

    @Test func manyThreadsAtOnceCompleteItOnce() {
        for _ in 0..<50 {
            let calls = Calls()
            let once = OnceCompletion { calls.add($0) }
            let firsts = Calls()
            DispatchQueue.concurrentPerform(iterations: 64) { i in
                if once.finish(success: i.isMultiple(of: 2)) { firsts.add(true) }
            }
            #expect(calls.all.count == 1)
            #expect(firsts.all.count == 1)
        }
    }
}
#endif
