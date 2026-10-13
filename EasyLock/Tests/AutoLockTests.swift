import AppKit

@main
struct AutoLockTests {
    @MainActor static func main() async {
        let workspace = NotificationCenter(), distributed = NotificationCenter()
        var now = 1000.0
        var count = 0
        let controller = AutoLockController(workspace: workspace, distributed: distributed, installMonitors: false, now: { now })
        controller.onLock = { count += 1 }
        controller.minutes = 1
        now += 59; controller.checkIdle(); precondition(count == 0)
        controller.touch(); now += 59; controller.checkIdle(); precondition(count == 0)
        now += 1; controller.checkIdle(); precondition(count == 1)
        controller.minutes = 0; now += 10000; controller.checkIdle(); precondition(count == 1)
        for event in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.post(name: event, object: nil)
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(count == 4)
        distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        try? await Task.sleep(nanoseconds: 20_000_000)
        precondition(count == 5)
        // Registration smoke test against the actual macOS notification centers (no events sent).
        let real = AutoLockController()
        real.touch()
        print("PASS: idle timeout, activity reset, disabled idle timer, sleep/session/lock notifications and real observer registration")
    }
}
