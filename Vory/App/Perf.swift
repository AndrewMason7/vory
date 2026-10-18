import Foundation
import os

/// DEBUG only: counts how often the heavy views re-evaluate, printed once a second to the log
/// (`log stream --predicate 'subsystem == "Vory" AND category == "perf"'`). Reads as a
/// per-second "how much work did a scroll cause" figure; zero cost in Release.
enum Perf {
    #if DEBUG
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    private static let lock = NSLock()
    private static let log = Logger(subsystem: "Vory", category: "perf")
    nonisolated(unsafe) private static var timer: Timer?

    static func tick(_ name: String) {
        lock.lock(); counts[name, default: 0] += 1; lock.unlock()
        if timer == nil {
            DispatchQueue.main.async {
                guard timer == nil else { return }
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in flush() }
            }
        }
    }

    private static func flush() {
        lock.lock(); let snapshot = counts; counts = [:]; lock.unlock()
        guard !snapshot.isEmpty else { return }
        let line = snapshot.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        log.notice("\(line, privacy: .public)")
    }

    nonisolated(unsafe) private static var watching = false
    /// Time the whole process stood still (suspended by the system), from the heartbeat.
    nonisolated(unsafe) private static var frozenNanos: UInt64 = 0

    /// How long the main thread kept the screen waiting, measured: a thread of its own asks the
    /// main thread to answer every 50 ms and logs each wait over a quarter of a second ("main
    /// thread busy 1840 ms"), the freeze a person feels as taps that do nothing. Testers came
    /// back to a long turn and found the app frozen; this is how a fix is checked. A second
    /// thread beats every 20 ms; a gap in its beats is the system suspending the app, which is
    /// taken out of the wait rather than blamed on the main thread.
    /// The shortest wait the watch logs: 250 ms, or what `-vory-perf-stall-ms` asks for, for a UI test that holds a
    /// screen to a tighter bound (#421: the full-call sheet, 100 ms).
    static let stallMs: UInt64 = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-vory-perf-stall-ms"), i + 1 < a.count, let v = UInt64(a[i + 1]), v > 0 { return v }
        return 250
    }()

    static func watchMainThread() {
        guard !watching else { return }
        watching = true
        let heartbeat = Thread {
            var last = DispatchTime.now().uptimeNanoseconds
            while true {
                Thread.sleep(forTimeInterval: 0.02)
                let now = DispatchTime.now().uptimeNanoseconds
                if now - last > 200_000_000 { lock.lock(); frozenNanos += now - last; lock.unlock() }
                last = now
            }
        }
        heartbeat.name = "dev.vory.main-thread-watch.beat"
        heartbeat.start()
        let thread = Thread {
            let answered = DispatchSemaphore(value: 0)
            while true {
                lock.lock(); let frozenBefore = frozenNanos; lock.unlock()
                let asked = DispatchTime.now().uptimeNanoseconds
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let waited = DispatchTime.now().uptimeNanoseconds - asked
                // The heartbeat reports a suspension when it next beats: a moment later.
                Thread.sleep(forTimeInterval: 0.05)
                lock.lock(); let frozen = frozenNanos - frozenBefore; lock.unlock()
                let ms = (waited > frozen ? waited - frozen : 0) / 1_000_000
                if ms >= stallMs { log.notice("main thread busy \(ms) ms") }
            }
        }
        thread.name = "dev.vory.main-thread-watch"
        thread.qualityOfService = .utility
        thread.start()
    }
    /// One line in the perf log, for a timing measured in place (a panel's first layout, say).
    static func note(_ line: String) { log.notice("\(line, privacy: .public)") }
    /// A note with the time in ms, for the order of events across views (the back swipe).
    static func stamp(_ line: String) { note("\(Int((DispatchTime.now().uptimeNanoseconds / 1_000_000) % 1_000_000)) " + line) }
    #else
    @inline(__always) static func tick(_ name: String) {}
    @inline(__always) static func watchMainThread() {}
    @inline(__always) static func note(_ line: String) {}
    @inline(__always) static func stamp(_ line: String) {}
    #endif
}
