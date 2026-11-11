import Darwin
import Foundation
import XCTest
@testable import WalnutAgent

final class EngineInspectorTests: XCTestCase {
    func testCancelledInspectorAllowsOwnedAdapterToCleanUpAfterWrapperExits() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        let input = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "trap 'exit 0' TERM; /bin/sh -c \"$2\" adapter \"$1\" & wait", "wrapper", log.path,
            """
            release() {
                /bin/sleep 0.15
                printf 'released\\n' >> "$1"
                exit 0
            }
            trap 'release "$1"' TERM
            printf 'ready\\n' > "$1"
            while :; do /bin/sleep 1; done
            """
        ]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let group = EngineInspector.ownedProcessGroup(process)
        defer {
            if process.isRunning { Darwin.kill(group.map { -$0 } ?? process.processIdentifier, SIGKILL) }
        }
        XCTAssertEqual(group, process.processIdentifier)
        let readyBy = ContinuousClock.now + .seconds(2)
        while !FileManager.default.fileExists(atPath: log.path), ContinuousClock.now < readyBy {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.path))

        let stop = Task {
            await EngineInspector.stop(process, processGroup: group, input: input.fileHandleForWriting,
                                       eofGrace: .milliseconds(50), terminationGrace: .seconds(2))
        }
        stop.cancel()
        await stop.value

        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "ready\nreleased\n")
    }

    func testBlockedOutputFailsWithinBoundAndRestoresDescriptorFlags() throws {
        let pipe = Pipe()
        let descriptor = pipe.fileHandleForWriting.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        let start = ContinuousClock.now
        XCTAssertThrowsError(try EngineInspector.writeFrame(Data(repeating: 0x61, count: 2 * 1024 * 1024),
                                                            to: descriptor, timeoutMs: 30)) { error in
            XCTAssertTrue(error.localizedDescription.contains("stopped accepting output"))
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        XCTAssertEqual(fcntl(descriptor, F_GETFL) & O_NONBLOCK, flags & O_NONBLOCK)
        withExtendedLifetime(pipe) {}
    }

    func testInspectorRequiresOneExplicitDeviceAndTransport() throws {
        let usb = try EngineInspector.Options(["--udid", "01234567-0123456789ABCDEF", "--usb"])
        XCTAssertTrue(usb.usb)
        XCTAssertFalse(usb.wifi)
        let wifi = try EngineInspector.Options(["--udid", "01234567-0123456789ABCDEF", "--wifi"])
        XCTAssertTrue(wifi.wifi)
        XCTAssertThrowsError(try EngineInspector.Options([]))
        XCTAssertThrowsError(try EngineInspector.Options(["--udid", "localhost:1234"]))
        XCTAssertThrowsError(try EngineInspector.Options(["--udid", "ABC", "--usb", "--wifi"]))
    }

    func testCDPCommandCannotUseInternalIDOrBypassTargetScope() throws {
        let command = try EngineInspector.Command(Data(#"{"id":2,"method":"Debugger.enable"}"#.utf8))
        XCTAssertEqual(command.id, 2)
        XCTAssertEqual(command.method, "Debugger.enable")
        for invalid in [
            #"{"id":true,"method":"Debugger.enable"}"#,
            #"{"id":0,"method":"Debugger.enable"}"#,
            #"{"id":2147483648,"method":"Debugger.enable"}"#,
            #"{"id":2,"method":"Debugger.enable","sessionId":"other"}"#,
            #"{"id":2,"method":"Debugger.enable","params":[]}"#
        ] {
            XCTAssertThrowsError(try EngineInspector.Command(Data(invalid.utf8)))
        }
    }
}
