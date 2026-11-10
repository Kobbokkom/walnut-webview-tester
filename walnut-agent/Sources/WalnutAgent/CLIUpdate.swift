import Darwin
import Foundation

enum CLIUpdate {
    static func run() async throws {
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &path, UInt32(path.count)) > 0 else {
            throw AgentError("Could not locate the running Walnut Agent executable.")
        }
        let executable = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
        let bundlePath = ["Walnut Agent.app", "Contents", "MacOS", "walnut-agent"]
        guard executable.pathComponents.suffix(bundlePath.count).elementsEqual(bundlePath) else {
            throw installationError
        }
        let installation = URL(fileURLWithPath: NSString.path(withComponents: Array(executable.pathComponents.dropLast(bundlePath.count))))
        let manual = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/walnut-agent").resolvingSymlinksInPath()
        if installation.path == manual.path {
            try await ManualUpdate.run(installation: manual, currentVersion: CLI.version)
            return
        }

        let cask = installation.deletingLastPathComponent()
        let caskroom = cask.deletingLastPathComponent()
        guard cask.lastPathComponent == "walnut-agent", caskroom.lastPathComponent == "Caskroom" else {
            throw installationError
        }
        let brew = caskroom.deletingLastPathComponent().appendingPathComponent("bin/brew")
        guard FileManager.default.isExecutableFile(atPath: brew.path) else {
            throw AgentError("Could not locate the Homebrew that installed Walnut Agent.")
        }
        let tap = try runCommand(brew, ["--repository", "kobbokkom/tap"], captureOutput: true)
        guard tap.hasPrefix("/") else { throw AgentError("Could not locate the Walnut Agent Homebrew tap.") }
        try runCommand(URL(fileURLWithPath: "/usr/bin/git"), ["-C", tap, "pull", "--ff-only"])

        // Installing an outdated cask upgrades it without running Homebrew's global upgrade hooks.
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] = "1"
        environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        environment.removeValue(forKey: "HOMEBREW_NO_INSTALL_UPGRADE")
        try runCommand(brew, ["install", "--cask", "kobbokkom/tap/walnut-agent"], environment: environment)
    }

    @discardableResult
    private static func runCommand(
        _ executable: URL, _ arguments: [String], captureOutput: Bool = false, environment: [String: String]? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let output = captureOutput ? Pipe() : nil
        if let output { process.standardOutput = output }
        try process.run()
        let data = output?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw AgentError("Could not update Walnut Agent. See the command output above.")
        }
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw AgentError("Homebrew returned an invalid tap path.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let installationError = AgentError(
        "Install Walnut Agent with Homebrew or the official ZIP before running update. If you built from source, pull the repository and rebuild."
    )
}
