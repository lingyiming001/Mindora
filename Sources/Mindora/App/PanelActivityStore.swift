import AppKit

extension Notification.Name {
    static let mindoraMainWindowDidClose = Notification.Name("Mindora.MainWindowDidClose")
}

/// Window-bound requests, including future assistant requests, must register here.
@MainActor final class PanelActivityStore {
    static let shared = PanelActivityStore()
    private var isActive = true
    private var cancellations: [UUID: () -> Void] = [:]
    @discardableResult func register<Success: Sendable, Failure: Error>(_ task: Task<Success, Failure>) -> UUID {
        let id = UUID()
        guard isActive else { task.cancel(); return id }
        cancellations[id] = { task.cancel() }; return id
    }
    func finish(_ id: UUID) { cancellations.removeValue(forKey: id) }
    func resume() { isActive = true }
    func cancelAll() {
        isActive = false
        let pending = Array(cancellations.values)
        cancellations.removeAll()
        for cancel in pending { cancel() }
    }
}
