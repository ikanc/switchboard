import ServiceManagement
import SwiftUI

// SMAppService.mainApp.register() only succeeds when the app runs from
// /Applications (or ~/Applications). Toggling from an Xcode/DerivedData build
// will throw — that's expected; install via publish.sh first.
fileprivate enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum AppView: Equatable {
    case list
    case addService(isOneShot: Bool)
    case editService(ServiceConfig)
    case duplicateService(ServiceConfig)
}

enum ListTab: String, CaseIterable, Identifiable {
    case services
    case commands

    var id: String { rawValue }
    var label: String {
        switch self {
        case .services: return "Services"
        case .commands: return "Commands"
        }
    }
}

struct ServiceListView: View {
    @ObservedObject var manager: ServiceManager
    @State private var currentView: AppView = .list
    @State private var selectedTab: ListTab = .services
    @State private var expandedService: String?
    @State private var serviceToDelete: ServiceConfig?
    @State private var showDeleteConfirm = false
    @State private var launchAtLoginEnabled: Bool = LaunchAtLogin.isEnabled
    @ObservedObject private var sleepPreventer = SleepPreventer.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            switch currentView {
            case .list:
                listView
            case .addService(let isOneShot):
                ServiceFormView(
                    mode: .add,
                    defaultIsOneShot: isOneShot,
                    onSave: { config in
                        manager.addService(config)
                        selectedTab = config.isOneShot ? .commands : .services
                        withAnimation { currentView = .list }
                    },
                    onCancel: { withAnimation { currentView = .list } }
                )
            case .editService(let config):
                ServiceFormView(
                    mode: .edit(config),
                    onSave: { config in
                        manager.updateService(config)
                        selectedTab = config.isOneShot ? .commands : .services
                        withAnimation { currentView = .list }
                    },
                    onCancel: { withAnimation { currentView = .list } }
                )
            case .duplicateService(let source):
                ServiceFormView(
                    mode: .add,
                    defaultIsOneShot: source.isOneShot,
                    prefill: source,
                    onSave: { config in
                        manager.addService(config)
                        selectedTab = config.isOneShot ? .commands : .services
                        withAnimation { currentView = .list }
                    },
                    onCancel: { withAnimation { currentView = .list } }
                )
            }
        }
        .background(.ultraThinMaterial)
        .alert("Delete", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let config = serviceToDelete {
                    manager.deleteService(config)
                }
            }
        } message: {
            Text("Delete \"\(serviceToDelete?.name ?? "")\"? This can't be undone.")
        }
    }

    // MARK: - List

    private var visibleServices: [ServiceProcess] {
        manager.services.filter { selectedTab == .services ? !$0.config.isOneShot : $0.config.isOneShot }
    }

    // Moves the row at `index` (within the current tab's visible list) by `delta`
    // positions (-1 = up, +1 = down). Bridges to SwiftUI's insert-before offset
    // convention used by moveServices.
    private func moveRow(at index: Int, by delta: Int) {
        let target = index + delta
        guard target >= 0, target < visibleServices.count, target != index else { return }
        // Move(from:to:) uses insert-before offsets: moving down needs +1 extra.
        let destination = delta > 0 ? target + 1 : target
        let isOneShot = selectedTab == .commands
        manager.moveServices(
            matching: { $0.isOneShot == isOneShot },
            from: IndexSet([index]),
            to: destination
        )
    }

    private var listView: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()

            if visibleServices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(visibleServices.enumerated()), id: \.element.id) { idx, service in
                            ServiceRowView(
                                service: service,
                                isExpanded: expandedService == service.id,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedService = expandedService == service.id ? nil : service.id
                                    }
                                },
                                onEdit: {
                                    withAnimation { currentView = .editService(service.config) }
                                },
                                onDuplicate: {
                                    withAnimation { currentView = .duplicateService(service.config) }
                                },
                                onDelete: {
                                    serviceToDelete = service.config
                                    showDeleteConfirm = true
                                },
                                onMoveUp: { moveRow(at: idx, by: -1) },
                                onMoveDown: { moveRow(at: idx, by: 1) },
                                canMoveUp: idx > 0,
                                canMoveDown: idx < visibleServices.count - 1
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
            Text("Switchboard")
                .font(.headline)
            Spacer()
            if selectedTab == .services {
                Text("\(manager.runningCount)/\(manager.totalServiceCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
            } else {
                Text("\(visibleServices.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(ListTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: emptyStateIcon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(emptyStateSubtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                withAnimation {
                    currentView = .addService(isOneShot: selectedTab == .commands)
                }
            } label: {
                Label(selectedTab == .commands ? "Add Command" : "Add Service", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateIcon: String {
        selectedTab == .commands ? "terminal" : "plus.circle.dashed"
    }

    private var emptyStateTitle: String {
        selectedTab == .commands ? "No commands yet" : "No services configured"
    }

    private var emptyStateSubtitle: String {
        selectedTab == .commands
            ? "One-time commands run once and exit"
            : "Add your first service to get started"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if selectedTab == .services {
                Button {
                    manager.startAll()
                } label: {
                    Label("Start All", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(manager.allRunning || manager.totalServiceCount == 0)

                Button {
                    manager.stopAll()
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!manager.anyRunning)
            }

            Spacer()

            Button {
                withAnimation {
                    currentView = .addService(isOneShot: selectedTab == .commands)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.bordered)

            // Open the full window for in-depth control. Closing it later leaves
            // services running (the menu-bar dropdown stays the quick surface).
            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Open the main window")

            // Keep-awake toggle. Highlighted (filled cup + tint) while active so
            // it's an obvious reminder the lid-close sleep override is on.
            Button {
                sleepPreventer.toggle()
            } label: {
                Image(systemName: sleepPreventer.isEnabled ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(sleepPreventer.isEnabled ? .orange : .secondary)
            .help(sleepPreventer.isEnabled
                ? "Staying awake with the lid closed — click to allow sleep again"
                : "Keep the Mac awake with the lid closed")

            Menu {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchAtLoginEnabled = newValue
                        } catch {
                            NSLog("Launch at Login toggle failed: \(error.localizedDescription)")
                            launchAtLoginEnabled = LaunchAtLogin.isEnabled
                        }
                    }
                ))
                Divider()
                Button("About Switchboard") { AboutPanelPresenter.shared.show() }
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                manager.stopAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "power")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
