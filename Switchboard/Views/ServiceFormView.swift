import SwiftUI

enum FormMode: Equatable {
    case add
    case edit(ServiceConfig)
}

struct ServiceFormView: View {
    let mode: FormMode
    var defaultIsOneShot: Bool = false
    var prefill: ServiceConfig? = nil
    let onSave: (ServiceConfig) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var command: String = ""
    @State private var workingDirectory: String = ""
    @State private var portString: String = ""
    @State private var selectedIcon: String = "terminal.fill"
    @State private var selectedColor: String = "blue"
    @State private var isOneShot: Bool = false
    @State private var group: String = ""
    @State private var envVars: [EnvVar] = []

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var headerTitle: String {
        let noun = isOneShot ? "Command" : "Service"
        return (isEditing ? "Edit " : "Add ") + noun
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespaces).isEmpty &&
        !workingDirectory.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
                Text(headerTitle)
                    .font(.headline)
                Spacer()

                // Invisible spacer for centering
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    fieldSection("Name") {
                        TextField("e.g. Frontend, API Server", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Command
                    fieldSection("Command") {
                        TextField("e.g. npm run dev", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    // Working Directory
                    fieldSection("Working Directory") {
                        HStack(spacing: 8) {
                            TextField("~/Code/my-project", text: $workingDirectory)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button {
                                pickFolder()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Group / project
                    fieldSection("Group (optional)") {
                        TextField("e.g. My App, Side Project", text: $group)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Environment variables
                    fieldSection("Environment Variables (optional)") {
                        envEditor
                    }

                    // One-shot toggle
                    fieldSection("Type") {
                        Toggle(isOn: $isOneShot) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("One-time command")
                                    .font(.system(.body, weight: .medium))
                                Text("Runs once and exits. No auto-restart, no port watching.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    // Port (optional) - only for long-running services
                    if !isOneShot {
                        fieldSection("Port (optional - enables auto-kill on conflict)") {
                            TextField("e.g. 3000", text: $portString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    }

                    // Icon
                    fieldSection("Icon") {
                        iconPicker
                    }

                    // Color
                    fieldSection("Color") {
                        colorPicker
                    }

                    // Preview
                    fieldSection("Preview") {
                        previewCard
                    }
                }
                .padding(16)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                Spacer()
                Button(isEditing ? "Save Changes" : (isOneShot ? "Add Command" : "Add Service")) {
                    save()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear {
            if case .edit(let config) = mode {
                name = config.name
                command = config.command
                workingDirectory = config.workingDirectory
                selectedIcon = config.icon
                selectedColor = config.colorName
                portString = config.port.map { String($0) } ?? ""
                isOneShot = config.isOneShot
                group = config.group ?? ""
                envVars = config.environment
            } else if let source = prefill {
                // Duplicate: pre-fill all fields; save() will mint a new UUID.
                name = source.name + " (copy)"
                command = source.command
                workingDirectory = source.workingDirectory
                selectedIcon = source.icon
                selectedColor = source.colorName
                portString = source.port.map { String($0) } ?? ""
                isOneShot = source.isOneShot
                group = source.group ?? ""
                envVars = source.environment
            } else {
                isOneShot = defaultIsOneShot
            }
        }
    }

    private var envEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($envVars) { $env in
                HStack(spacing: 6) {
                    TextField("KEY", text: $env.key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Text("=").foregroundStyle(.tertiary)
                    TextField("value", text: $env.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Button {
                        envVars.removeAll { $0.id == env.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                envVars.append(EnvVar())
            } label: {
                Label("Add variable", systemImage: "plus").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            content()
        }
    }

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 10), spacing: 6) {
            ForEach(ServiceConfig.availableIcons, id: \.self) { icon in
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 30, height: 30)
                        .background(selectedIcon == icon ? ServiceConfig.colorMap[selectedColor]?.opacity(0.2) ?? Color.blue.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selectedIcon == icon ? (ServiceConfig.colorMap[selectedColor] ?? .blue) : .clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedIcon == icon ? (ServiceConfig.colorMap[selectedColor] ?? .blue) : .secondary)
            }
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 8) {
            ForEach(ServiceConfig.availableColors, id: \.name) { item in
                Button {
                    selectedColor = item.name
                } label: {
                    Circle()
                        .fill(item.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: selectedColor == item.name ? 2 : 0)
                        )
                        .shadow(color: selectedColor == item.name ? item.color.opacity(0.5) : .clear, radius: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var previewCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((ServiceConfig.colorMap[selectedColor] ?? .blue).opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: selectedIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(ServiceConfig.colorMap[selectedColor] ?? .blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Service Name" : name)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(name.isEmpty ? .tertiary : .primary)
                Text("Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .frame(width: 26, height: 26)
                .background(Color.green.opacity(0.12))
                .clipShape(Circle())
        }
        .padding(10)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the project directory"

        if panel.runModal() == .OK, let url = panel.url {
            // Convert to ~ path if under home dir
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if url.path.hasPrefix(homePath) {
                workingDirectory = url.path.replacingOccurrences(of: homePath, with: "~")
            } else {
                workingDirectory = url.path
            }
        }
    }

    private func save() {
        var config: ServiceConfig
        if case .edit(let existing) = mode {
            config = existing
        } else {
            config = ServiceConfig(name: "", command: "", workingDirectory: "")
        }
        config.name = name.trimmingCharacters(in: .whitespaces)
        config.command = command.trimmingCharacters(in: .whitespaces)
        config.workingDirectory = workingDirectory.trimmingCharacters(in: .whitespaces)
        config.icon = selectedIcon
        config.colorName = selectedColor
        config.port = isOneShot ? nil : Int(portString)
        config.isOneShot = isOneShot
        let trimmedGroup = group.trimmingCharacters(in: .whitespaces)
        config.group = trimmedGroup.isEmpty ? nil : trimmedGroup
        config.environment = envVars
            .map { EnvVar(id: $0.id, key: $0.key.trimmingCharacters(in: .whitespaces), value: $0.value) }
            .filter { !$0.key.isEmpty }
        onSave(config)
    }
}
