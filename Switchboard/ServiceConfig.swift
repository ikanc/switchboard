import SwiftUI

// A single environment variable applied to a service's process. Ordered (array,
// not dict) so the editor has stable rows.
struct EnvVar: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var key: String = ""
    var value: String = ""
}

struct ServiceConfig: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var command: String
    var workingDirectory: String
    var icon: String
    var colorName: String
    var port: Int?
    var isOneShot: Bool
    // Optional project/profile this service belongs to. nil = "Ungrouped".
    var group: String?
    // Per-service environment variables, exported before the command runs.
    var environment: [EnvVar]

    init(id: String = UUID().uuidString, name: String, command: String, workingDirectory: String, icon: String = "terminal", colorName: String = "blue", port: Int? = nil, isOneShot: Bool = false, group: String? = nil, environment: [EnvVar] = []) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.icon = icon
        self.colorName = colorName
        self.port = port
        self.isOneShot = isOneShot
        self.group = group
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, command, workingDirectory, icon, colorName, port, isOneShot, group, environment
    }

    // Custom decoder so configs saved before newer fields existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        command = try c.decode(String.self, forKey: .command)
        workingDirectory = try c.decode(String.self, forKey: .workingDirectory)
        icon = try c.decode(String.self, forKey: .icon)
        colorName = try c.decode(String.self, forKey: .colorName)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        isOneShot = try c.decodeIfPresent(Bool.self, forKey: .isOneShot) ?? false
        group = try c.decodeIfPresent(String.self, forKey: .group)
        environment = try c.decodeIfPresent([EnvVar].self, forKey: .environment) ?? []
    }

    var expandedPath: String {
        NSString(string: workingDirectory).expandingTildeInPath
    }

    var color: Color {
        Self.colorMap[colorName] ?? .blue
    }

    // MARK: - Available Options

    static let availableColors: [(name: String, color: Color)] = [
        ("blue", .blue),
        ("green", .green),
        ("purple", .purple),
        ("orange", .orange),
        ("cyan", .cyan),
        ("red", .red),
        ("pink", .pink),
        ("yellow", .yellow),
        ("indigo", .indigo),
        ("mint", .mint),
    ]

    static let colorMap: [String: Color] = Dictionary(uniqueKeysWithValues: availableColors.map { ($0.name, $0.color) })

    static let availableIcons: [String] = [
        "globe", "network", "brain", "safari", "graduationcap",
        "gearshape.2", "server.rack", "terminal.fill", "hammer.fill",
        "wrench.and.screwdriver", "cpu", "iphone", "desktopcomputer",
        "bolt.fill", "flame.fill", "leaf.fill", "doc.text", "folder.fill",
        "cloud.fill", "lock.fill", "envelope.fill", "phone.fill",
        "paintbrush.fill", "wand.and.stars", "cart.fill", "building.2",
        "house.fill", "car.fill", "briefcase.fill", "storefront.fill",
    ]

    // MARK: - Defaults (first launch)

    // Illustrative placeholders shown on first launch — edit or delete them to
    // point at your own projects. These are generic examples, not real paths.
    static let defaults: [ServiceConfig] = [
        ServiceConfig(name: "Web App", command: "npm run dev", workingDirectory: "~/code/web-app", icon: "globe", colorName: "blue", port: 3000),
        ServiceConfig(name: "API", command: "npm run dev", workingDirectory: "~/code/api", icon: "server.rack", colorName: "green", port: 8000),
        ServiceConfig(name: "Tunnel", command: "ngrok http 3000", workingDirectory: "~", icon: "network", colorName: "purple"),
        ServiceConfig(name: "Install deps", command: "npm install", workingDirectory: "~/code/web-app", icon: "wrench.and.screwdriver", colorName: "orange", isOneShot: true),
    ]
}
