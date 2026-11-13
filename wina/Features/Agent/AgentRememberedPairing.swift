import CryptoKit
import Foundation
import Security

struct AgentRememberedPairing: Codable, Equatable {
    let key: Data
    let serviceName: String

    static func load() throws -> Self? { try store.load() }
    func save() throws { try Self.store.save(self) }
    static func forget() throws { try store.forget() }

    private static var store: Store {
        Store(
            directory: URL.applicationSupportDirectory.appendingPathComponent("WalnutAgent", isDirectory: true),
            account: "remembered-mac"
        )
    }

    struct Store {
        let directory: URL
        let account: String

        private var installationKeyURL: URL { directory.appendingPathComponent("installation-key") }
        private var query: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.kobbokkom.wina.agent",
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: false,
            ]
        }

        func load() throws -> AgentRememberedPairing? {
            guard let key = try installationKey() else { return nil }
            var search = query
            search[kSecReturnData as String] = true
            search[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(search as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try check(status)
            guard let encrypted = result as? Data, encrypted.count <= 1024,
                  let box = try? AES.GCM.SealedBox(combined: encrypted),
                  let data = try? AES.GCM.open(box, using: key) else {
                throw StorageError.invalidRecord
            }
            let pairing = try JSONDecoder().decode(AgentRememberedPairing.self, from: data)
            try pairing.validate()
            return pairing
        }

        func save(_ pairing: AgentRememberedPairing) throws {
            try pairing.validate()
            let existingKey = try installationKey()
            let key = existingKey ?? SymmetricKey(size: .bits256)
            let data = try JSONEncoder().encode(pairing)
            guard let encrypted = try AES.GCM.seal(data, using: key).combined else {
                throw StorageError.invalidRecord
            }
            let attributes = [
                kSecValueData as String: encrypted,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ] as [String: Any]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                try check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
            } else {
                try check(status)
            }
            // Write a new installation key only after replacing any stale Keychain record.
            if existingKey == nil { try saveInstallationKey(key) }
        }

        func forget() throws {
            // Invalidate access before deleting the Keychain item, even if deletion then fails.
            var fileError: Error?
            do {
                try FileManager.default.removeItem(at: installationKeyURL)
            } catch CocoaError.fileNoSuchFile {
                // Already invalidated.
            } catch {
                fileError = error
            }
            let status = SecItemDelete(query as CFDictionary)
            if let fileError, status != errSecSuccess, status != errSecItemNotFound {
                throw fileError
            }
        }

        private func installationKey() throws -> SymmetricKey? {
            do {
                let bytes = try Data(contentsOf: installationKeyURL)
                guard bytes.count == 32 else { throw StorageError.invalidRecord }
                return SymmetricKey(data: bytes)
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            }
        }

        private func saveInstallationKey(_ key: SymmetricKey) throws {
            // App deletion removes this file even if the Keychain item survives.
            var folder = directory
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete]
            )
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try folder.setResourceValues(resources)
            try key.withUnsafeBytes { Data($0) }.write(to: installationKeyURL, options: [.atomic, .completeFileProtection])
        }

        private func check(_ status: OSStatus) throws {
            guard status == errSecSuccess else { throw StorageError.keychain(status) }
        }
    }

    private func validate() throws {
        guard key.count == 32, (1...63).contains(serviceName.utf8.count),
              !serviceName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw StorageError.invalidRecord
        }
    }

    private enum StorageError: LocalizedError {
        case invalidRecord
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidRecord: "Could not read the saved Mac pairing."
            case .keychain(let status): "Could not access the saved Mac pairing (Keychain error \(status))."
            }
        }
    }
}
