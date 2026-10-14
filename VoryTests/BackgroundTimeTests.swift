#if os(iOS)
import Foundation
import Testing
@testable import Vory
@testable import VoryCore

/// #371: background time is answered off the main thread. With `beginBackgroundTask` the
/// system's "time is up" came on the main thread, and a main thread busy with a long turn's
/// events could not answer it in the seconds allowed, so the system ended the app. Here the
/// main thread is held while the time runs out, as such a turn holds it: the time has to be
/// given back anyway, and a watch request still gets exactly one answer.
@MainActor @Suite struct BackgroundTimeTests {
    /// A stand-in for the system's expiring activity: runs the block on a queue of its own, as
    /// the system does, and says the time is up when the test asks.
    final class FakeActivity: @unchecked Sendable {
        private let lock = NSLock()
        private var block: (@Sendable (Bool) -> Void)?
        /// Signalled when the first call returns: the time is given back.
        let returned = DispatchSemaphore(value: 0)

        var start: BackgroundTime.Start {
            { [self] _, block in
                lock.withLock { self.block = block }
                DispatchQueue.global().async {
                    block(false)
                    self.returned.signal()
                }
            }
        }

        /// The system saying the time is up, from another queue.
        func expire() {
            let b = lock.withLock { block }
            DispatchQueue.global().async { b?(true) }
        }
    }

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        func append(_ t: T) { lock.withLock { items.append(t) } }
        var all: [T] { lock.withLock { items } }
    }

    @Test func theTimeUpIsAnsweredWithTheMainThreadBusy() {
        let fake = FakeActivity()
        let onMain = Box<Bool>()
        let ran = DispatchSemaphore(value: 0)
        let time = BackgroundTime("unit", start: fake.start) {
            onMain.append(Thread.isMainThread)
            ran.signal()
        }
        fake.expire()
        // The main thread stays blocked here, in the waits, until both have happened.
        #expect(ran.wait(timeout: .now() + 5) == .success, "the time-up handler did not run while the main thread was busy")
        #expect(fake.returned.wait(timeout: .now() + 5) == .success, "the time was not given back while the main thread was busy")
        #expect(onMain.all == [false])
        withExtendedLifetime(time) {}
    }

    @Test func endingGivesTheTimeBackAndEndingTwiceIsHarmless() {
        let fake = FakeActivity()
        let time = BackgroundTime("unit", start: fake.start)
        #expect(fake.returned.wait(timeout: .now() + 0.3) == .timedOut, "the time was given back before the work ended")
        time.end()
        #expect(fake.returned.wait(timeout: .now() + 5) == .success)
        time.end()
    }

    @Test func timeDroppedWithoutEndingIsGivenBack() {
        let fake = FakeActivity()
        _ = BackgroundTime("unit", start: fake.start)
        #expect(fake.returned.wait(timeout: .now() + 5) == .success)
    }

    @Test func aWatchRequestOutOfTimeIsAnsweredOnceWithTheMainThreadBusy() {
        let fake = FakeActivity()
        let answers = Box<[String: Any]>()
        let got = DispatchSemaphore(value: 0)
        let hold = WatchRequestHold(reply: { answers.append($0); got.signal() }, start: fake.start)
        fake.expire()
        #expect(got.wait(timeout: .now() + 5) == .success, "the watch was not answered while the main thread was busy")
        #expect(fake.returned.wait(timeout: .now() + 5) == .success, "the time was not given back while the main thread was busy")
        // The work finishing later does not answer a second time.
        hold.finish(["ok": true])
        #expect(answers.all.count == 1)
        #expect(answers.all.first.map(RelayWire.isUnavailable) == true)
    }

    @Test func aFinishedWatchRequestIsAnsweredOnceAndGivesTheTimeBack() {
        let fake = FakeActivity()
        let answers = Box<[String: Any]>()
        let hold = WatchRequestHold(reply: { answers.append($0) }, start: fake.start)
        hold.finish(["ok": true])
        #expect(fake.returned.wait(timeout: .now() + 5) == .success)
        fake.expire()
        Thread.sleep(forTimeInterval: 0.2)
        hold.finish(["ok": true])
        #expect(answers.all.count == 1)
        #expect(answers.all.first?["ok"] as? Bool == true)
    }
}
#endif
