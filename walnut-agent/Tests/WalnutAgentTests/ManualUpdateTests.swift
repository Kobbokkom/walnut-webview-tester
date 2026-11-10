import Darwin
import Foundation
import XCTest
@testable import WalnutAgent

final class ManualUpdateTests: XCTestCase {
    func testChoosesHighestPublishedWalnutVersion() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let releases = try decoder.decode([ManualUpdate.Release].self, from: Data("""
        [
          {"tag_name":"walnut-agent-v1.2.0","draft":false,"prerelease":false,"assets":[]},
          {"tag_name":"v9.0.0","draft":false,"prerelease":false,"assets":[]},
          {"tag_name":"walnut-agent-v8.0.0","draft":true,"prerelease":false,"assets":[]},
          {"tag_name":"walnut-agent-v7.0.0","draft":false,"prerelease":true,"assets":[]},
          {"tag_name":"walnut-agent-v6.00.0","draft":false,"prerelease":false,"assets":[]},
          {"tag_name":"walnut-agent-v1.10.0","draft":false,"prerelease":false,"assets":[{
            "name":"walnut-agent-1.10.0-macos-universal.zip","size":42,"digest":"sha256:fixture",
            "browser_download_url":"https://github.com/Kobbokkom/walnut-webview-tester/releases/download/walnut-agent-v1.10.0/walnut-agent-1.10.0-macos-universal.zip"
          }]}
        ]
        """.utf8))
        let latest = try XCTUnwrap(ManualUpdate.newestRelease(in: releases))
        XCTAssertEqual(latest.tagName, "walnut-agent-v1.10.0")
        XCTAssertEqual(latest.assets.first?.browserDownloadUrl.lastPathComponent, "walnut-agent-1.10.0-macos-universal.zip")
    }

    func testExtractsKnownLayoutAndRejectsUnsafeEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixture = root.appendingPathComponent("fixture")
        let files = [
            "Walnut Agent.app/Contents/Info.plist",
            "Walnut Agent.app/Contents/MacOS/walnut-agent",
            "Walnut Agent.app/Contents/_CodeSignature/CodeResources",
            "Walnut Agent.app/Contents/CodeResources",
            "Walnut Agent.app/Contents/Resources/SKILL.md",
            "skill/SKILL.md"
        ]
        let manager = FileManager.default
        defer { try? manager.removeItem(at: root) }
        for path in files {
            let file = fixture.appendingPathComponent(path)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: file)
        }
        let valid = root.appendingPathComponent("valid.zip")
        let installed = root.appendingPathComponent("installed")
        try zip(fixture, to: valid)
        try ManualUpdate.extract(valid, to: installed)
        for path in files {
            XCTAssertEqual(try Data(contentsOf: installed.appendingPathComponent(path)), Data(path.utf8))
        }
        XCTAssertTrue(manager.isExecutableFile(atPath: installed.appendingPathComponent(files[1]).path))

        let unexpected = fixture.appendingPathComponent("extra")
        try Data("outside payload".utf8).write(to: unexpected)
        let malformed = root.appendingPathComponent("extra.zip")
        try zip(fixture, to: malformed)
        XCTAssertThrowsError(try ManualUpdate.extract(malformed, to: root.appendingPathComponent("unpacked-extra")))
        try manager.removeItem(at: unexpected)

        let skill = fixture.appendingPathComponent("skill/SKILL.md")
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try manager.removeItem(at: skill)
        try manager.createSymbolicLink(at: skill, withDestinationURL: outside)
        let linked = root.appendingPathComponent("symlink.zip")
        try zip(fixture, to: linked)
        XCTAssertThrowsError(try ManualUpdate.extract(linked, to: root.appendingPathComponent("unpacked-link")))
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))

        try manager.removeItem(at: skill)
        try Data(repeating: 0, count: 512 * 1024 + 1).write(to: skill)
        let oversized = root.appendingPathComponent("oversized.zip")
        try zip(fixture, to: oversized)
        XCTAssertThrowsError(try ManualUpdate.extract(oversized, to: root.appendingPathComponent("unpacked-large")))
    }

    func testRefusesToReplaceUnrecognizedOrSharedInstallation() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installation = root.appendingPathComponent("walnut-agent")
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: installation, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let extra = installation.appendingPathComponent("local-notes.txt")
        let original = Data("keep me".utf8)
        try original.write(to: extra)

        XCTAssertThrowsError(try ManualUpdate.install(Data([0]), version: "0.1.1", in: installation, currentVersion: "0.1.0")) {
            XCTAssertTrue($0.localizedDescription.contains("unrecognized layout"))
        }
        XCTAssertEqual(try Data(contentsOf: extra), original)
        XCTAssertEqual(chmod(root.path, 0o770), 0)
        XCTAssertThrowsError(try ManualUpdate.install(Data([0]), version: "0.1.1", in: installation, currentVersion: "0.1.0")) {
            XCTAssertTrue($0.localizedDescription.contains("writable only by you"))
        }
        XCTAssertEqual(try Data(contentsOf: extra), original)
    }

    private func zip(_ directory: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", directory.path, archive.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
