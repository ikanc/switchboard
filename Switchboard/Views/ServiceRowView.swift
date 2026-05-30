import SwiftUI

struct ServiceRowView: View {
    @ObservedObject var service: ServiceProcess
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isExpanded {
                logSection
            }
        }
        .background(isExpanded ? Color.primary.opacity(0.04) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .contextMenu {
            Button {
                service.start()
            } label: {
                Label(service.config.isOneShot ? "Run" : "Start", systemImage: "play.fill")
            }
            .disabled(service.status == .running || service.status == .starting)
            if !service.config.isOneShot {
                Button { service.restart() } label: { Label("Restart", systemImage: "arrow.clockwise") }
                    .disabled(service.status != .running)
            }
            Button { service.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .disabled(service.status != .running && service.status != .starting && service.status != .restarting)
            Divider()
            Button(action: onMoveUp) { Label("Move Up", systemImage: "arrow.up") }
                .disabled(!canMoveUp)
            Button(action: onMoveDown) { Label("Move Down", systemImage: "arrow.down") }
                .disabled(!canMoveDown)
            Divider()
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            statusDot
            serviceInfo
            Spacer()
            actionButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 28, height: 28)
            Image(systemName: service.config.icon)
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
        }
    }

    private var serviceInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(service.config.name)
                    .font(.system(.body, weight: .medium))
                if service.config.isOneShot {
                    Text("one-time")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 4) {
                Text(service.status.rawValue)
                    .foregroundStyle(statusColor)
                if service.status == .running {
                    // TimelineView only schedules ticks while it's on-screen,
                    // so the popover being closed automatically pauses uptime
                    // updates without any extra observer plumbing.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let uptime = service.uptime(at: context.date) {
                            Text("- \(uptime)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            switch service.status {
            case .stopped, .crashed, .finished:
                iconButton("play.fill", color: .green) { service.start() }
            case .running:
                if let port = service.config.port, !service.config.isOneShot,
                   let url = URL(string: "http://localhost:\(port)") {
                    iconButton("safari", color: .blue) { NSWorkspace.shared.open(url) }
                }
                if !service.config.isOneShot {
                    iconButton("arrow.clockwise", color: .orange) { service.restart() }
                }
                iconButton("stop.fill", color: .red) { service.stop() }
            case .starting, .restarting:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 26, height: 26)
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(service.logs.isEmpty ? "No output yet..." : lastLines(service.logs, count: 30))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .frame(height: 140)
                .onChange(of: service.logs) { _ in
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(service.logs, forType: .string)
                } label: {
                    Label("Copy Logs", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    service.clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func iconButton(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
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

    private func lastLines(_ text: String, count: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        let start = max(0, lines.count - count)
        return lines[start...].joined(separator: "\n")
    }
}
