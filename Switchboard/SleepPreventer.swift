import AppKit
import Foundation

/// Controls macOS "stay awake even with the lid closed" via `pmset disablesleep`.
///
/// `pmset disablesleep` is the only switch that survives a lid close on a
/// MacBook with no external display — `IOPMAssertion`/`caffeinate` only block
/// *idle* sleep while the lid is open. It requires root.
///
/// To avoid an admin prompt on every toggle, the first change installs a
/// tightly-scoped `sudoers` rule (`/etc/sudoers.d/switchboard-pmset`) that lets
/// exactly the two `pmset -a disablesleep 0|1` commands run password-free for
/// the current user. After that one prompt, every toggle runs via `sudo -n`
/// silently — no password, no Touch ID, no nag.
///
/// The kernel flag is cleared by a reboot, so the live `pmset -g` state
/// (readable without privileges) is the single source of truth: the toggle
/// always reflects reality and the highlighted icon reminds you when it's on.
@MainActor
final class SleepPreventer: ObservableObject {
    static let shared = SleepPreventer()

    @Published private(set) var isEnabled: Bool

    private static let sudoersPath = "/etc/sudoers.d/switchboard-pmset"

    private init() {
        isEnabled = Self.systemSleepDisabled()
    }

    /// Flip the toggle. Tries the password-free path first; on the very first
    /// use (or if the sudoers rule is missing) it falls back to a single admin
    /// prompt that installs the rule *and* applies the change. Returns false if
    /// the privileged call failed or was cancelled — state is left untouched.
    @discardableResult
    func toggle() -> Bool {
        let target = isEnabled ? 0 : 1

        if Self.applySilently(target) || Self.installRuleAndApply(target) {
            isEnabled = (target == 1)
            return true
        }
        return false
    }

    // MARK: - Apply paths

    /// Fast path: `sudo -n pmset …`. Succeeds only once the sudoers rule exists.
    private static func applySilently(_ target: Int) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "\(target)"])
    }

    /// Slow path (one-time): admin prompt installs the scoped sudoers rule, then
    /// applies the change. Subsequent toggles take the silent path above.
    private static func installRuleAndApply(_ target: Int) -> Bool {
        // The install runs as root (via the admin prompt), so the final pmset
        // needs no sudo. The rule is validated with `visudo -cf` before it's put
        // in place; if validation fails the change is still applied this once.
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        // Single line on purpose: AppleScript string literals can't carry raw
        // newlines, and its own \n escaping would mangle a multi-line payload.
        let script = "TMP=$(mktemp); echo '\(rule)' > \"$TMP\"; "
            + "if /usr/sbin/visudo -cf \"$TMP\"; then /usr/bin/install -m 0440 -o root -g wheel \"$TMP\" '\(sudoersPath)'; fi; "
            + "rm -f \"$TMP\"; /usr/bin/pmset -a disablesleep \(target)"
        return runPrivileged(script)
    }

    // MARK: - State

    /// Reads the live flag from `pmset -g` — no privileges required.
    private static func systemSleepDisabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        // The relevant line reads e.g. " SleepDisabled        1"
        return output.split(separator: "\n").contains { line in
            line.contains("SleepDisabled") && line.split(separator: " ").last == "1"
        }
    }

    // MARK: - Process helpers

    /// Runs an executable and returns true on a zero exit status.
    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Runs `script` as root via a native macOS admin-authentication prompt.
    private static func runPrivileged(_ script: String) -> Bool {
        let source = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        guard let apple = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        apple.executeAndReturnError(&error)
        if let error {
            NSLog("[Switchboard] pmset disablesleep failed: \(error)")
            return false
        }
        return true
    }
}
