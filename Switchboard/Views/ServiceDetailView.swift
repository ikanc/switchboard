import SwiftUI

// In-depth control surface for a single service, shown in the main window's
// detail pane: status + controls, quick actions, configuration, and a large
// live log view.
struct ServiceDetailView: View {
    @ObservedObject var service: ServiceProcess
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var config: ServiceConfig { service.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    quickActions
                    configSection
                    if !config.environment.isEmpty {
                        envSection
                    }
                }
                .padding(16)
            }
            Divider()
            logPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(config.color.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: config.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(config.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name).font(.title3.weight(.semibold))
                    if let group = config.group, !group.isEmpty {
                        Text(group)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    if config.isOneShot {
                        Text("one-time")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text(service.status.rawValue).foregroundStyle(statusColor)
                    if service.status == .running {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if let uptime = service.uptime(at: context.date) {
                                Text("· \(uptime)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.caption)
            }
            Spacer()
            controls
        }
        .padding(16)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch service.status {
            case .stopped, .crashed, .finished:
                Button {
                    service.start()
                } label: { Label(config.isOneShot ? "Run" : "Start", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(.green)
            case .running:
                if !config.isOneShot {
                    Button { service.restart() } label: { Label("Restart", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                }
                Button { service.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.bordered).tint(.red)
            case .starting, .restarting:
                ProgressView().scaleEffect(0.7).frame(width: 28)
                Button { service.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.bordered).tint(.red)
            }

            Menu {
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                Divider()
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 8) {
            if service.localURL != nil {
                actionChip("Open URL", "safari") { service.openInBrowser() }
            }
            actionChip("Finder", "folder") { service.openWorkingDirectory() }
            actionChip("Terminal", "terminal") { service.openInTerminal() }
            actionChip("Copy command", "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(config.command, forType: .string)
            }
            Spacer()
        }
    }

    private func actionChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Configuration")
            infoRow("Command", config.command, mono: true)
            infoRow("Directory", config.workingDirectory, mono: true)
            if let port = config.port {
                infoRow("Port", "\(port)")
            }
        }
    }

    private var envSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Environment (\(config.environment.count))")
            ForEach(config.environment) { env in
                HStack(spacing: 6) {
                    Text(env.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("=")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(env.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(mono ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Logs

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Logs").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(service.logs.strippingANSI, forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc").font(.caption2) }
                    .buttonStyle(.bordered).controlSize(.mini)
                Button { service.clearLogs() } label: {
                    Label("Clear", systemImage: "trash").font(.caption2)
                }
                .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(service.logs.isEmpty ? "No output yet…" : service.logs.strippingANSI)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .id("logBottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: service.logs) { _ in
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
            .frame(height: 240)
        }
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
