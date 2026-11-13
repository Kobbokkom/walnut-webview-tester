import Darwin
import Foundation
import WalnutPairing

struct AgentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}

struct Pairing: Codable, Equatable {
    let version: Int
    let serviceName: String
    let port: UInt16
    let key: Data

    static var file: URL {
        if let path = ProcessInfo.processInfo.environment["WALNUT_AGENT_CONFIG"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/walnut-agent/pairing.json")
    }

    static func fromToken(_ input: String) throws -> Self {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "walnut-agent:"
        guard token.hasPrefix(prefix), token.utf8.count <= 1024 else { throw invalidPairing }
        var encoded = String(token.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { throw invalidPairing }
        let pairing = try decode(data)
        guard pairing.version == 1 else { throw invalidPairing }
        return pairing
    }

    static func fromFile(at file: URL) throws -> Self {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AgentError("Could not open the pairing file.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == getuid(),
              status.st_size <= 1024,
              let data = try handle.read(upToCount: 1025), data.count <= 1024,
              let token = String(data: data, encoding: .utf8) else {
            throw AgentError("The pairing file must be a UTF-8 text file owned by your user and no larger than 1 KiB.")
        }
        return try fromToken(token)
    }

    static func load(from file: URL) throws -> Self {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw AgentError("Pair with Walnut using `walnut-agent pair` before connecting.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == getuid(),
              status.st_mode & 0o077 == 0,
              status.st_size <= 1024,
              let data = try handle.read(upToCount: 1025), data.count <= 1024 else {
            throw AgentError("The pairing file must be a private file owned by your user. Run `walnut-agent pair` again.")
        }
        return try decode(data)
    }

    func save(to file: URL) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let template = directory.appendingPathComponent(".pairing.XXXXXX").path
        var buffer = Array(template.utf8CString)
        let descriptor = mkstemp(&buffer)
        guard descriptor >= 0 else { throw AgentError("Could not create the private pairing file.") }
        let path = String(cString: buffer)
        defer { unlink(path) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: JSONEncoder().encode(self))
        try handle.close()
        guard rename(path, file.path) == 0 else { throw AgentError("Could not save the pairing file.") }
    }

    private static var invalidPairing: AgentError { AgentError("Invalid Walnut pairing token.") }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1024, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.version == 1 || (value.version == 2 && value.port == PairingWire.rememberedPort),
              value.port != 0, value.key.count == 32,
              (1...63).contains(value.serviceName.utf8.count),
              !value.serviceName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw invalidPairing
        }
        return value
    }
}
