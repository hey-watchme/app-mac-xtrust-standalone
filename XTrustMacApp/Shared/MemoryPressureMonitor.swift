import Darwin
import Dispatch
import Foundation

final class MemoryPressureMonitor: @unchecked Sendable {

    enum PressureLevel: String, Sendable {
        case normal = "Normal"
        case warning = "Warning"
        case critical = "Critical"
    }

    struct Event: Sendable {
        enum Kind: Sendable {
            case pressureChanged(PressureLevel)
            case subprocessKilled(pid: pid_t, label: String)
        }
        let timestamp: Date
        let kind: Kind
    }

    private let lock = NSLock()
    private var source: (any DispatchSourceMemoryPressure)?
    private var registeredProcesses: [pid_t: String] = [:]
    private var eventLog: [Event] = []
    private var _currentLevel: PressureLevel = .normal
    private let maxEventLog = 20

    var currentLevel: PressureLevel {
        lock.withLock { _currentLevel }
    }

    var recentEvents: [Event] {
        lock.withLock { eventLog }
    }

    func start() {
        lock.withLock {
            guard source == nil else { return }
            let src = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: .global(qos: .userInteractive)
            )
            src.setEventHandler { [weak self] in
                let data = src.data
                self?.handleEvent(data)
            }
            src.resume()
            source = src
        }
    }

    func stop() {
        lock.withLock {
            source?.cancel()
            source = nil
        }
    }

    func register(pid: pid_t, label: String) {
        lock.withLock { registeredProcesses[pid] = label }
    }

    func unregister(pid: pid_t) {
        lock.withLock { _ = registeredProcesses.removeValue(forKey: pid) }
    }

    private func handleEvent(_ event: DispatchSource.MemoryPressureEvent) {
        let level: PressureLevel =
            event.contains(.critical) ? .critical :
            event.contains(.warning)  ? .warning  : .normal

        lock.withLock {
            _currentLevel = level
            appendToLog(Event(timestamp: Date(), kind: .pressureChanged(level)))
        }

        guard event.contains(.critical) else { return }

        var toKill: [pid_t: String] = [:]
        lock.withLock {
            toKill = registeredProcesses
            registeredProcesses.removeAll()
        }

        for (pid, label) in toKill {
            Darwin.kill(pid, SIGKILL)
            lock.withLock {
                appendToLog(Event(timestamp: Date(), kind: .subprocessKilled(pid: pid, label: label)))
            }
        }
    }

    private func appendToLog(_ event: Event) {
        eventLog.append(event)
        if eventLog.count > maxEventLog { eventLog.removeFirst() }
    }
}
