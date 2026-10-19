#if os(iOS)
import BackgroundTasks
import Foundation
import os

/// A completion that runs once, however many times and from whichever threads it is asked for: a
/// background task's expiration and its work can both end it, and a second completion is a fault
/// the system reports (#422: the daily backup task was completed twice when its time ran out).
final class OnceCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let complete: (Bool) -> Void

    init(_ complete: @escaping (Bool) -> Void) { self.complete = complete }

    /// Completes with `success` if nothing has yet; whether this call was the one that did.
    @discardableResult func finish(success: Bool) -> Bool {
        lock.lock()
        let first = !completed
        completed = true
        lock.unlock()
        if first { complete(success) }
        return first
    }
}

/// The daily iCloud backup when the app is not open: a BGAppRefreshTask the system runs when
/// it sees fit (best effort, roughly daily), asked for each time the app goes to the
/// background. It runs the same quiet backup the app runs on coming forward. (The Mac has
/// its own scheduler, NSBackgroundActivityScheduler, in VoryMac.)
enum CloudBackupTask {
    private static let log = Logger(subsystem: "dev.vory", category: "backup")

    /// Once, at launch: the handler for the task the Info.plist permits.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: CloudSync.backupTaskID, using: nil) { task in
            // The task comes on the scheduler's queue and is completed from the expiration handler
            // or from the main actor, whichever comes first, and once: when the time ran out before
            // the backup finished, both completed it (#422). Completing from any thread is fine.
            let once = OnceCompletion { task.setTaskCompleted(success: $0) }
            // Time up before the backup ran (the main actor was busy): the task is given back
            // unfinished; without this the system ends the app for an unfinished task.
            task.expirationHandler = { once.finish(success: false) }
            Task { @MainActor in
                CloudSync.shared.backUpIfDue()
                log.notice("daily backup task ran; last own backup \(CloudSync.shared.lastOwnBackupAt?.description ?? "none", privacy: .public)\(CloudSync.shared.lastAutoBackupError.map { "; " + $0 } ?? "", privacy: .public)")
                if !once.finish(success: CloudSync.shared.lastAutoBackupError == nil) { log.notice("daily backup task: its time ran out first") }
                schedule()
            }
        }
    }

    /// Where the request is submitted: a serial queue of its own, so two quick leaves submit one
    /// after the other (the later replacing the earlier, as the scheduler does) and never at once.
    private static let submitter = DispatchQueue(label: "dev.vory.backup-schedule", qos: .utility)

    /// Ask for the next run, a day out at the earliest; a request already pending is replaced.
    /// Off the main thread: submitting is a call into the system made at every leave, where the
    /// main thread's time belongs to the system's snapshot of the app (#422).
    static func schedule() {
        submitter.async {
            let request = BGAppRefreshTaskRequest(identifier: CloudSync.backupTaskID)
            request.earliestBeginDate = Date(timeIntervalSinceNow: CloudSync.backupInterval)
            do { try BGTaskScheduler.shared.submit(request) } catch {
                // Not permitted on this device (Low Power Mode, a simulator): the app's own
                // activation path still backs up when it is due.
                log.notice("daily backup task not scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
