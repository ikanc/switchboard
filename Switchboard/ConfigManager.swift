import Foundation

class ConfigManager {
    static let shared = ConfigManager()

    private let configURL: URL

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Switchboard")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("services.json")
    }

    func load() -> [ServiceConfig] {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let defaults = ServiceConfig.defaults
            save(defaults)
            return defaults
        }

        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode([ServiceConfig].self, from: data)
        } catch {
            print("[Switchboard] Failed to load config: \(error). Using defaults.")
            let defaults = ServiceConfig.defaults
            save(defaults)
            return defaults
        }
    }

    func save(_ configs: [ServiceConfig]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(configs)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[Switchboard] Failed to save config: \(error)")
        }
    }

    var configPath: String {
        configURL.path
    }
}
