import Foundation

struct AgentPairingFile: Identifiable {
    let url: URL
    var id: URL { url }

    init(code: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Walnut-pairing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [
            .posixPermissions: 0o700,
            .protectionKey: FileProtectionType.complete,
        ])
        url = directory.appendingPathComponent("Walnut-pairing.txt")
        do {
            try Data(code.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
