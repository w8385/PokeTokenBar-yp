import AppKit
import CoreGraphics
import Foundation

/// Measures active seconds between ticks from a monotonic clock and the system idle time.
/// The wall clock is never read, so changing it cannot create time.
struct ActiveTimeMeter {
    private var lastTick: TimeInterval?
    private var lastWasActive = false

    /// Forget the previous tick: the next one only sets the anchor. Called on sleep, lock and mode changes.
    mutating func reanchor() {
        lastTick = nil
        lastWasActive = false
    }

    /// `uptime` excludes sleep. `idle` is seconds since the last keyboard or pointer event.
    mutating func step(uptime: TimeInterval, idle: TimeInterval, present: Bool) -> TimeInterval {
        guard present else {
            reanchor()
            return 0
        }
        let active = idle <= PokemonBalance.timeIdleLimit
        defer {
            lastTick = uptime
            lastWasActive = active
        }
        guard let last = lastTick, uptime > last, active else { return 0 }
        let gap = min(uptime - last, PokemonBalance.timeMaxStep)
        return lastWasActive ? gap : min(gap, idle)
    }
}

/// Reads whether the Mac is in use. Needs no permission: the idle query returns only an elapsed time and
/// never sees which keys or buttons were pressed.
@MainActor
final class ActivityMonitor {
    /// Called when sleep, screen sleep or the lock begins or ends.
    var onBreak: (() -> Void)?
    private var asleep = false
    private var screenOff = false
    private var locked = false
    private var switchedOut = false
    private var observers: [NSObjectProtocol] = []

    var isPresent: Bool { !asleep && !screenOff && !locked && !switchedOut }

    var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0) ?? .null)
    }

    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.willSleepNotification) { $0.asleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.asleep = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screenOff = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screenOff = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.switchedOut = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.switchedOut = false }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ change: @escaping @MainActor (ActivityMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
                self.onBreak?()
            }
        }
        observers.append(token)
    }
}
