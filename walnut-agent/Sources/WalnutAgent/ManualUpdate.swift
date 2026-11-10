import CryptoKit
import Darwin
import Foundation

enum ManualUpdate {
    private static let repository = "Kobbokkom/walnut-webview-tester"
    private static let tagPrefix = "walnut-agent-v"
    private static let appName = "Walnut Agent.app"
    private static let archiveLimit = 16 * 1024 * 1024
    private static let executable = "\(appName)/Contents/MacOS/walnut-agent"
    private static let skill = "skill/SKILL.md"
    private static let sealedSkill = "\(appName)/Contents/Resources/SKILL.md"

    struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        var version: [Int]? {
            guard !draft, !prerelease, tagName.hasPrefix(ManualUpdate.tagPrefix) else { return nil }
            return ManualUpdate.versionParts(String(tagName.dropFirst(ManualUpdate.tagPrefix.count)))
        }
    }

    struct Asset: Decodable {
        let name: String
        let size: Int
        let digest: String?
        let browserDownloadUrl: URL
    }

    static func run(installation: URL, currentVersion: String) async throws {
        guard let installed = versionParts(currentVersion) else { throw AgentError("Invalid installed Walnut Agent version.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        guard let release = try await latestRelease(using: session), let version = release.version else {
            throw AgentError("No published Walnut Agent release was found.")
        }
        guard installed.lexicographicallyPrecedes(version) else {
            report("Walnut Agent \(currentVersion) is up to date.")
            return
        }
        let versionString = version.map(String.init).joined(separator: ".")
        let assetName = "walnut-agent-\(versionString)-macos-universal.zip"
        let url = URL(string: "https://github.com/\(repository)/releases/download/\(release.tagName)/\(assetName)")!
        guard let asset = release.assets.first(where: { $0.name == assetName }),
              asset.browserDownloadUrl == url, (1...archiveLimit).contains(asset.size),
              let digest = asset.digest, digest.hasPrefix("sha256:"), digest.utf8.count == 71 else {
            throw AgentError("The Walnut Agent release is missing its verified macOS ZIP.")
        }

        let (data, _) = try await fetch(url, limit: asset.size, using: session)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == asset.size, digest == "sha256:\(checksum)" else {
            throw AgentError("The Walnut Agent download failed its SHA-256 check.")
        }
        try install(data, version: versionString, in: installation, currentVersion: currentVersion)
        report("Updated Walnut Agent to \(versionString).")
    }

    private static func latestRelease(using session: URLSession) async throws -> Release? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var page = 1
        var newest: Release?
        while true {
            let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100&page=\(page)")!
            let (data, response) = try await fetch(url, limit: 8 * 1024 * 1024, using: session)
            guard response.url == url else { throw AgentError("Unexpected Walnut Agent release endpoint.") }
            let releases = try decoder.decode([Release].self, from: data)
            if let candidate = newestRelease(in: releases + (newest.map { [$0] } ?? [])) { newest = candidate }
            guard response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true else { return newest }
            page += 1
        }
    }

    static func newestRelease(in releases: [Release]) -> Release? {
        releases.compactMap { release in release.version.map { ($0, release) } }
            .max { $0.0.lexicographicallyPrecedes($1.0) }?.1
    }

    private static func versionParts(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard parts.count == 3, numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }),
              numbers.map(String.init).joined(separator: ".") == text else { return nil }
        return numbers
    }

    private static func fetch(_ url: URL, limit: Int, using session: URLSession) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("walnut-agent", forHTTPHeaderField: "User-Agent")
        let (bytes, rawResponse) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = rawResponse as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.expectedContentLength <= limit else {
            throw AgentError("Could not fetch the Walnut Agent release from GitHub.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw AgentError("The Walnut Agent download exceeded its expected size.") }
            data.append(byte)
        }
        return (data, response)
    }

    static func install(_ data: Data, version: String, in installation: URL, currentVersion: String) throws {
        guard let old = versionParts(currentVersion), let new = versionParts(version), old.lexicographicallyPrecedes(new),
              (1...archiveLimit).contains(data.count) else { throw AgentError("Invalid Walnut Agent upgrade.") }
        let parent = installation.deletingLastPathComponent()
        guard isOwned(parent, type: S_IFDIR) else {
            throw AgentError("The Walnut Agent parent folder must be owned by you and writable only by you.")
        }
        let lockURL = parent.appendingPathComponent(".walnut-agent-update.lock")
        let lock = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw AgentError("Could not lock the Walnut Agent installation.") }
        defer { close(lock) }
        var lockStat = stat()
        guard fstat(lock, &lockStat) == 0, lockStat.st_mode & S_IFMT == S_IFREG, lockStat.st_mode & 0o022 == 0,
              lockStat.st_uid == geteuid(), lockStat.st_nlink == 1, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            throw AgentError("Another Walnut Agent update is active, or its lock is unavailable.")
        }

        let metadata = try ownedMetadata(in: installation)
        try verifyBundle(in: installation, version: currentVersion, assess: false)
        let scratch = parent.appendingPathComponent(".walnut-update-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: scratch) }

        let archive = scratch.appendingPathComponent("release.zip")
        let candidate = scratch.appendingPathComponent("candidate", isDirectory: true)
        try data.write(to: archive, options: .withoutOverwriting)
        try extract(archive, to: candidate)
        try verifyBundle(in: candidate, version: version, assess: true)
        for path in metadata {
            try fm.copyItem(at: installation.appendingPathComponent(path), to: candidate.appendingPathComponent(path))
        }
        let permissions = try fm.attributesOfItem(atPath: installation.path)[.posixPermissions]
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: candidate.path) }
        guard isOwned(parent, type: S_IFDIR), try ownedMetadata(in: installation) == metadata else {
            throw AgentError("The Walnut Agent installation changed during the update. Try again.")
        }
        try verifyBundle(in: installation, version: currentVersion, assess: false)
        try Task.checkCancellation()
        // Both directories are on the installation volume, and the bin symlink keeps the same target.
        guard renamex_np(candidate.path, installation.path, UInt32(RENAME_SWAP)) == 0 else {
            throw AgentError("Could not replace Walnut Agent. The previous installation is still in place.")
        }
    }

    private static func ownedMetadata(in installation: URL) throws -> [String] {
        let fm = FileManager.default
        let expectedRoot: Set<String> = [appName, "skill"]
        let expectedSkill: Set<String> = ["SKILL.md"]
        var metadata: [String] = []
        for (path, expected) in [("", expectedRoot), ("skill", expectedSkill)] {
            let directory = path.isEmpty ? installation : installation.appendingPathComponent(path)
            guard isOwned(directory, type: S_IFDIR), let contents = try? fm.contentsOfDirectory(atPath: directory.path),
                  Set(contents).subtracting([".DS_Store"]) == expected else {
                throw AgentError("The Walnut Agent folder contains an unrecognized layout. Update with the install guide.")
            }
            if contents.contains(".DS_Store") {
                let metadataPath = path.isEmpty ? ".DS_Store" : "\(path)/.DS_Store"
                guard isOwned(installation.appendingPathComponent(metadataPath), type: S_IFREG) else {
                    throw AgentError("Unrecognized Finder metadata in the Walnut Agent installation.")
                }
                metadata.append(metadataPath)
            }
        }
        return metadata
    }

    private static func isOwned(_ url: URL, type: mode_t) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == type && info.st_mode & 0o022 == 0 &&
            info.st_uid == geteuid() &&
            (type != S_IFREG || info.st_nlink == 1)
    }

    private static func verifyBundle(in installation: URL, version: String, assess: Bool) throws {
        let app = installation.appendingPathComponent(appName)
        let requirement = #"anchor apple generic and identifier "com.kobbokkom.walnut-agent" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "X6M5USK89L""#
        guard isOwned(app, type: S_IFDIR), isOwned(installation.appendingPathComponent(executable), type: S_IFREG) else {
            throw AgentError("Unrecognized Walnut Agent application bundle.")
        }
        _ = try tool("/usr/bin/codesign", ["--verify", "--strict", "--all-architectures", "-R=\(requirement)", app.path],
                     limit: 4096, failure: "The Walnut Agent Developer ID signature could not be verified.")
        let plist = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        guard info?["CFBundleShortVersionString"] as? String == version else {
            throw AgentError("The signed Walnut Agent version differs from the requested version. Restart and try again.")
        }
        let skillURL = installation.appendingPathComponent(skill)
        let sealedURL = installation.appendingPathComponent(sealedSkill)
        guard isOwned(skillURL, type: S_IFREG), isOwned(sealedURL, type: S_IFREG),
              FileManager.default.contentsEqual(atPath: skillURL.path, andPath: sealedURL.path) else {
            throw AgentError("The Walnut Agent skill differs from its signed copy. Update with the install guide.")
        }
        if assess {
            let message = "Gatekeeper could not verify Walnut Agent notarization."
            let result = try tool("/usr/sbin/spctl", ["--assess", "--type", "execute", "--raw", app.path],
                                  limit: 32 * 1024, failure: message)
            let assessment = try PropertyListSerialization.propertyList(from: result, format: nil) as? [String: Any]
            let authority = assessment?["assessment:authority"] as? [String: Any]
            guard assessment?["assessment:verdict"] as? Bool == true,
                  authority?["assessment:authority:source"] as? String == "Notarized Developer ID" else {
                throw AgentError(message)
            }
        }
    }

    static func extract(_ archive: URL, to destination: URL) throws {
        let files = [
            executable: archiveLimit,
            "\(appName)/Contents/Info.plist": 64 * 1024,
            "\(appName)/Contents/_CodeSignature/CodeResources": 512 * 1024,
            "\(appName)/Contents/CodeResources": 512 * 1024,
            skill: 512 * 1024,
            sealedSkill: 512 * 1024
        ]
        let directories: Set<String> = [
            "\(appName)/", "\(appName)/Contents/", "\(appName)/Contents/MacOS/",
            "\(appName)/Contents/_CodeSignature/", "\(appName)/Contents/Resources/", "skill/"
        ]
        let failure = "The Walnut Agent ZIP contains an unexpected entry."
        let listing = try tool("/usr/bin/tar", ["-tf", archive.path], limit: 4096, failure: failure)
        guard let names = String(bytes: listing, encoding: .utf8) else { throw AgentError(failure) }
        let paths = names.split(separator: "\n").map(String.init)
        let entries = Set(paths)
        guard entries.count == paths.count, entries.subtracting(directories) == Set(files.keys) else { throw AgentError(failure) }

        let manager = FileManager.default
        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try manager.createDirectory(at: destination, withIntermediateDirectories: false, attributes: permissions)
        for path in directories.sorted() {
            try manager.createDirectory(at: destination.appendingPathComponent(path), withIntermediateDirectories: false, attributes: permissions)
        }
        // Read only fixed regular-file payloads. Archive paths, links, modes and metadata never reach disk.
        for (name, limit) in files {
            let data = try tool("/usr/bin/tar", ["-xOf", archive.path, "--no-mac-metadata", name], limit: limit, failure: failure)
            guard !data.isEmpty else { throw AgentError(failure) }
            let output = destination.appendingPathComponent(name)
            try data.write(to: output, options: .withoutOverwriting)
            guard chmod(output.path, name == executable ? 0o755 : 0o644) == 0 else {
                throw AgentError("Could not set Walnut Agent file permissions.")
            }
        }
    }

    private static func tool(_ executable: String, _ arguments: [String], limit: Int, failure: String) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: min(8192, limit - data.count + 1)), !chunk.isEmpty {
            guard chunk.count <= limit - data.count else { throw AgentError(failure) }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw AgentError(failure) }
        return data
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data("\(message)\n".utf8))
    }
}
