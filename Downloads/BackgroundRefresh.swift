import Foundation
import SwiftData

#if !targetEnvironment(macCatalyst)
import BackgroundTasks

/// Best-effort background update check. iOS decides if and when this runs.
enum BackgroundRefresh {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "folioreader") + ".refresh" }

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule()
            let work = Task { @MainActor in
                await LibraryUpdater.shared.runIfNeeded(context: container.mainContext)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: LibraryUpdater.minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#else
enum BackgroundRefresh {
    static func register(container: ModelContainer) {}
    static func schedule() {}
}
#endif
