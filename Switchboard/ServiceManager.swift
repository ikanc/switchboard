import Foundation
import Combine

class ServiceManager: ObservableObject {
    @Published var services: [ServiceProcess] = []
    @Published var configs: [ServiceConfig] = []

    private var cancellables = Set<AnyCancellable>()
    private let configManager = ConfigManager.shared

    private var longRunningServices: [ServiceProcess] {
        services.filter { !$0.config.isOneShot }
    }

    var allRunning: Bool {
        let svcs = longRunningServices
        return !svcs.isEmpty && svcs.allSatisfy { $0.status == .running }
    }

    var anyRunning: Bool {
        services.contains { $0.status == .running }
    }

    var runningCount: Int {
        longRunningServices.filter { $0.status == .running }.count
    }

    var totalServiceCount: Int {
        longRunningServices.count
    }

    init() {
        loadServices()
    }

    // MARK: - Config Management

    func loadServices() {
        configs = configManager.load()
        rebuildProcesses()
    }

    func addService(_ config: ServiceConfig) {
        configs.append(config)
        saveAndRebuild()
    }

    func updateService(_ config: ServiceConfig) {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else { return }

        // Stop if running
        if let process = services.first(where: { $0.id == config.id }), process.status == .running {
            process.stop()
        }

        configs[index] = config
        saveAndRebuild()
    }

    func deleteService(_ config: ServiceConfig) {
        // Stop if running
        if let process = services.first(where: { $0.id == config.id }) {
            process.stop()
        }

        configs.removeAll { $0.id == config.id }
        saveAndRebuild()
    }

    func moveService(from source: IndexSet, to destination: Int) {
        configs.move(fromOffsets: source, toOffset: destination)
        saveAndRebuild()
    }

    // Reorder only items matching `predicate`, keeping non-matching items at their
    // original positions in the configs array. Used so drag-to-reorder on one tab
    // doesn't disturb the other tab's ordering.
    func moveServices(matching predicate: (ServiceConfig) -> Bool, from source: IndexSet, to destination: Int) {
        let originalIndices = configs.indices.filter { predicate(configs[$0]) }
        guard !originalIndices.isEmpty else { return }
        var filtered = originalIndices.map { configs[$0] }
        filtered.move(fromOffsets: source, toOffset: destination)
        for (i, idx) in originalIndices.enumerated() {
            configs[idx] = filtered[i]
        }
        saveAndRebuild()
    }

    private func saveAndRebuild() {
        configManager.save(configs)
        rebuildProcesses()
    }

    private func rebuildProcesses() {
        // Preserve running state for existing services
        let runningStates = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })

        var newServices: [ServiceProcess] = []
        for config in configs {
            if let existing = runningStates[config.id] {
                existing.config = config
                newServices.append(existing)
            } else {
                newServices.append(ServiceProcess(config: config))
            }
        }

        // Stop any removed services
        for old in services where !configs.contains(where: { $0.id == old.id }) {
            old.stop()
        }

        services = newServices
        cancellables.removeAll()

        // Only propagate status changes to the manager so derived state
        // (runningCount, allRunning, menubar icon) updates. Log updates fire
        // their own @Published on the service and are handled by ServiceRowView
        // directly — no need to invalidate the entire view tree on each log line.
        for service in services {
            service.$status
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    // MARK: - Bulk Actions

    func startAll() {
        for service in services where service.status != .running {
            service.start()
        }
    }

    func stopAll() {
        for service in services {
            service.stop()
        }
    }

    func restartAll() {
        for service in services where service.status == .running {
            service.restart()
        }
    }

    // MARK: - Groups / Profiles

    /// Distinct group names in first-seen order. `nil` (ungrouped) is appended
    /// last when ungrouped services exist.
    var groupNames: [String?] {
        var seen = Set<String>()
        var ordered: [String?] = []
        var hasUngrouped = false
        for service in services {
            if let group = service.config.group, !group.isEmpty {
                if seen.insert(group).inserted { ordered.append(group) }
            } else {
                hasUngrouped = true
            }
        }
        if hasUngrouped { ordered.append(nil) }
        return ordered
    }

    func services(in group: String?) -> [ServiceProcess] {
        services.filter { (($0.config.group?.isEmpty == false) ? $0.config.group : nil) == group }
    }

    /// Start every long-running service in a group (skips one-shots + already running).
    func startGroup(_ group: String?) {
        for service in services(in: group) where !service.config.isOneShot && service.status != .running && service.status != .starting {
            service.start()
        }
    }

    /// Stop every running service in a group.
    func stopGroup(_ group: String?) {
        for service in services(in: group) {
            service.stop()
        }
    }
}
