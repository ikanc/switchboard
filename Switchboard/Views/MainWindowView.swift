import SwiftUI

extension String {
    /// Strips ANSI/VT100 escape sequences (colors, cursor moves) so log output
    /// reads cleanly in the window instead of showing `[32m`-style garbage.
    var strippingANSI: String {
        replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
}

// The "in-depth control" surface — a full window alongside the menu-bar dropdown.
// Closing it leaves the app (and all services) running; it's reopened from the
// dropdown's window button.
struct MainWindowView: View {
    @ObservedObject var manager: ServiceManager
    @State private var selectedID: String?
    @State private var sheet: FormSheet?
    @State private var servicePendingDelete: ServiceConfig?

    enum FormSheet: Identifiable {
        case add
        case edit(ServiceConfig)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let config): return "edit-\(config.id)"
            }
        }
    }

    private var selectedService: ServiceProcess? {
        manager.services.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let service = selectedService {
                ServiceDetailView(
                    service: service,
                    onEdit: { sheet = .edit(service.config) },
                    onDuplicate: {
                        var copy = service.config
                        copy.id = UUID().uuidString
                        copy.name += " (copy)"
                        manager.addService(copy)
                    },
                    onDelete: { servicePendingDelete = service.config }
                )
                .id(service.id)
            } else {
                emptyDetail
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(item: $sheet) { which in
            formSheet(which)
        }
        .confirmationDialog(
            "Delete “\(servicePendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { servicePendingDelete != nil }, set: { if !$0 { servicePendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let config = servicePendingDelete {
                    if selectedID == config.id { selectedID = nil }
                    manager.deleteService(config)
                }
                servicePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { servicePendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        .onAppear {
            if selectedID == nil { selectedID = manager.services.first?.id }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedID) {
            ForEach(manager.groupNames, id: \.self) { group in
                Section {
                    ForEach(manager.services(in: group)) { service in
                        SidebarRow(service: service).tag(service.id)
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    manager.startAll()
                } label: { Label("Start All", systemImage: "play.fill") }
                .help("Start all services")
                .disabled(manager.allRunning || manager.totalServiceCount == 0)

                Button {
                    manager.stopAll()
                } label: { Label("Stop All", systemImage: "stop.fill") }
                .help("Stop all services")
                .disabled(!manager.anyRunning)

                Button {
                    sheet = .add
                } label: { Label("Add", systemImage: "plus") }
                .help("Add a service or command")
            }
        }
        .navigationTitle("Switchboard")
    }

    private func groupHeader(_ group: String?) -> some View {
        let running = manager.services(in: group).filter { $0.status == .running }.count
        let total = manager.services(in: group).filter { !$0.config.isOneShot }.count
        return HStack(spacing: 6) {
            Text(group ?? "Ungrouped")
            Spacer()
            if total > 0 {
                Text("\(running)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                manager.startGroup(group)
            } label: { Image(systemName: "play.fill").font(.system(size: 9)) }
                .buttonStyle(.plain)
                .help("Start this group")
                .disabled(total == 0 || running == total)
            Button {
                manager.stopGroup(group)
            } label: { Image(systemName: "stop.fill").font(.system(size: 9)) }
                .buttonStyle(.plain)
                .help("Stop this group")
                .disabled(manager.services(in: group).allSatisfy { $0.status != .running })
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Select a service")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Pick a service on the left to view logs and controls.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func formSheet(_ which: FormSheet) -> some View {
        let mode: FormMode = {
            switch which {
            case .add: return .add
            case .edit(let config): return .edit(config)
            }
        }()
        ServiceFormView(
            mode: mode,
            onSave: { config in
                switch which {
                case .add: manager.addService(config); selectedID = config.id
                case .edit: manager.updateService(config)
                }
                sheet = nil
            },
            onCancel: { sheet = nil }
        )
        .frame(width: 460, height: 600)
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    @ObservedObject var service: ServiceProcess

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Image(systemName: service.config.icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.config.name)
                    .font(.body)
                Text(service.status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if service.config.isOneShot {
                Image(systemName: "1.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch service.status {
        case .stopped: return .secondary
        case .starting: return .yellow
        case .running: return .green
        case .restarting: return .orange
        case .crashed: return .red
        case .finished: return .blue
        }
    }
}
