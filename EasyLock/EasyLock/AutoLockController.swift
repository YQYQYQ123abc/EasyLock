import AppKit

/// Observes app-local activity; no global input monitoring or accessibility permission.
@MainActor
final class AutoLockController {
    var minutes: Int = 5
    var onLock: (() -> Void)?
    private var lastActivity: TimeInterval
    private let now: () -> TimeInterval
    private var timer: Timer?
    private var inputMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributed: NotificationCenter = DistributedNotificationCenter.default(),
         installMonitors: Bool = true, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        lastActivity = now()
        if installMonitors { inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            self?.touch(); return event
        } }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name)
        }
        // Public notification delivery; the screen-lock notification is supplementary to workspace events.
        observe(distributed, Notification.Name("com.apple.screenIsLocked"))
        if installMonitors { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkIdle()
            }
        } }
    }
    func checkIdle() {
        guard minutes > 0 else { return }
        if now() - lastActivity >= Double(minutes * 60) { onLock?(); touch() }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onLock?() }
        }
        observers.append((center, token))
    }
    func touch() { lastActivity = now() }
    deinit {
        timer?.invalidate()
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        for (center, token) in observers { center.removeObserver(token) }
    }
}
