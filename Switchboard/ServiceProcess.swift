import AppKit
import Combine
import Foundation

enum ServiceStatus: String {
    case stopped = "Stopped"
    case starting = "Starting..."
    case running = "Running"
    case restarting = "Restarting..."
    case crashed = "Crashed"
    case finished = "Finished"
}

class ServiceProcess: ObservableObject, Identifiable {
    var config: ServiceConfig
    var id: String { config.id }

    @Published var status: ServiceStatus = .stopped
    @Published var logs: String = ""
    @Published var startedAt: Date?

    private var process: Process?
    private var outputPipe: Pipe?
    private var restartCount = 0
    private let maxRestarts = 3
    private let restartDelay: TimeInterval = 5
    private let maxLogSize = 50_000

    // Log coalescing: pipe handlers fire many times per second for chatty
    // services (vite, php artisan). Buffer chunks on a background queue and
    // flush to the @Published `logs` at most every 200ms so SwiftUI re-renders
    // a few times per second instead of dozens.
    private var pendingChunks: [String] = []
    private let chunkLock = NSLock()
    private var flushScheduled = false
    private let flushInterval: TimeInterval = 0.2

    deinit {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
    }

    init(config: ServiceConfig) {
        self.config = config
    }

    var uptime: String? { uptime(at: Date()) }

    func uptime(at now: Date) -> String? {
        guard let started = startedAt, status == .running else { return nil }
        let elapsed = now.timeIntervalSince(started)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    func start() {
        guard status != .running && status != .starting else { return }
        restartCount = 0
        launchProcess()
    }

    func stop() {
        let wasRunning = status == .running || status == .starting || status == .restarting
        status = .stopped
        startedAt = nil
        killProcessTree()
        if wasRunning {
            appendLog("[Switchboard] Service stopped by user.\n")
        }
    }

    func restart() {
        appendLog("[Switchboard] Restarting...\n")
        killProcessTree()
        status = .restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.restartCount = 0
            self?.launchProcess()
        }
    }

    func clearLogs() {
        logs = ""
    }

    private func launchProcess() {
        let path = config.expandedPath

        if !FileManager.default.fileExists(atPath: path) {
            appendLog("[Switchboard] Directory not found: \(path)\n")
            status = .crashed
            return
        }

        status = .starting
        appendLog("[Switchboard] Starting: \(config.command)\n")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Source nvm/shell profile since macOS apps don't get interactive shell env
        let shellInit = """
            eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
            """
        // Per-service env vars, single-quoted so values with spaces/symbols are
        // passed literally. Embedded single quotes are escaped the POSIX way.
        let envExports = config.environment
            .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "export \($0.key)='\($0.value.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: "\n")
        proc.arguments = ["-c", "\(shellInit)\n\(envExports)\ncd '\(path)' && \(config.command)"]
        proc.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                self?.enqueueLogChunk(output)
            }
        }

        proc.terminationHandler = { [weak self] terminatedProc in
            DispatchQueue.main.async {
                self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self?.flushPendingLogs()
                self?.handleTermination(exitCode: terminatedProc.terminationStatus)
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.startedAt = Date()
            status = .running
        } catch {
            appendLog("[Switchboard] Failed to start: \(error.localizedDescription)\n")
            status = .crashed
        }
    }

    private func handleTermination(exitCode: Int32) {
        process = nil

        guard status != .stopped else { return }

        appendLog("[Switchboard] Process exited with code \(exitCode).\n")

        // One-shot commands: run once, don't auto-restart or retry on port conflicts.
        if config.isOneShot {
            status = exitCode == 0 ? .finished : .crashed
            startedAt = nil
            return
        }

        // Detect port-in-use errors
        let portConflict = logs.contains("EADDRINUSE") || logs.contains("address already in use")
        if portConflict, let port = config.port {
            appendLog("[Switchboard] Port \(port) in use. Killing blocking process...\n")
            killProcessOnPort(port)
            restartCount = 0
            status = .restarting
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.status == .restarting else { return }
                self.launchProcess()
            }
            return
        }

        // Detect stale process conflicts (ngrok "already online", etc.)
        let staleConflict = logs.contains("already online") || logs.contains("ERR_NGROK_334")
        if staleConflict {
            appendLog("[Switchboard] Stale process detected. Killing old instance...\n")
            killStaleProcess()
            restartCount = 0
            status = .restarting
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.status == .restarting else { return }
                self.launchProcess()
            }
            return
        }

        if restartCount < maxRestarts {
            restartCount += 1
            status = .restarting
            appendLog("[Switchboard] Auto-restart \(restartCount)/\(maxRestarts) in \(Int(restartDelay))s...\n")
            DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in
                guard let self, self.status == .restarting else { return }
                self.launchProcess()
            }
        } else {
            status = .crashed
            appendLog("[Switchboard] Crashed \(maxRestarts) times. Stopped auto-restart.\n")
        }
    }

    private func killProcessOnPort(_ port: Int) {
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        killer.arguments = ["-c", "lsof -ti tcp:\(port) | xargs kill -9 2>/dev/null"]
        let pipe = Pipe()
        killer.standardOutput = pipe
        killer.standardError = pipe
        try? killer.run()
        killer.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog("[Switchboard] Killed stale process on port \(port).\n")
        } else {
            appendLog("[Switchboard] No process found on port \(port), retrying anyway.\n")
        }
    }

    private func killStaleProcess() {
        // Kill any existing process matching the command, excluding our own PID
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let executable = config.command.components(separatedBy: " ").first ?? config.command
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Find matching processes, exclude our app, kill them
        killer.arguments = ["-c", """
            pgrep -f '\(executable)' | while read pid; do
                if [ "$pid" != "\(ownPid)" ] && [ "$(ps -o ppid= -p $pid | tr -d ' ')" != "\(ownPid)" ]; then
                    kill -9 $pid 2>/dev/null
                fi
            done
            sleep 1
        """]
        try? killer.run()
        killer.waitUntilExit()
        appendLog("[Switchboard] Killed stale '\(executable)' processes.\n")
    }

    private func killProcessTree() {
        guard let proc = process else { return }
        let pid = proc.processIdentifier

        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        killer.arguments = ["-c", """
            kill_tree() {
                local children=$(pgrep -P $1 2>/dev/null)
                for child in $children; do
                    kill_tree $child
                done
                kill -TERM $1 2>/dev/null
            }
            kill_tree \(pid)
        """]
        try? killer.run()
        killer.waitUntilExit()

        if proc.isRunning {
            proc.terminate()
        }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        flushPendingLogs()
    }

    // Called from the pipe's background queue. Coalesces into a buffer and
    // schedules a single main-thread flush per `flushInterval` window.
    private func enqueueLogChunk(_ chunk: String) {
        chunkLock.lock()
        pendingChunks.append(chunk)
        let needsSchedule = !flushScheduled
        if needsSchedule { flushScheduled = true }
        chunkLock.unlock()

        guard needsSchedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + flushInterval) { [weak self] in
            self?.flushPendingLogs()
        }
    }

    private func flushPendingLogs() {
        chunkLock.lock()
        let combined = pendingChunks.joined()
        pendingChunks.removeAll(keepingCapacity: true)
        flushScheduled = false
        chunkLock.unlock()

        guard !combined.isEmpty else { return }
        appendLog(combined)
    }

    private func appendLog(_ text: String) {
        logs += text
        if logs.count > maxLogSize {
            let startIndex = logs.index(logs.endIndex, offsetBy: -maxLogSize)
            logs = String(logs[startIndex...])
        }
    }

    // MARK: - Quick actions

    /// The local URL this service serves on, if it declares a port.
    var localURL: URL? {
        guard let port = config.port, !config.isOneShot else { return nil }
        return URL(string: "http://localhost:\(port)")
    }

    /// Open the served URL (localhost:<port>) in the default browser.
    func openInBrowser() {
        guard let url = localURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Reveal the working directory in Finder.
    func openWorkingDirectory() {
        NSWorkspace.shared.open(URL(fileURLWithPath: config.expandedPath))
    }

    /// Open a new Terminal window at the working directory.
    func openInTerminal() {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = ["-a", "Terminal", config.expandedPath]
        try? opener.run()
    }
}
