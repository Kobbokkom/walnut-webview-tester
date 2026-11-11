import Darwin
import Foundation
import XCTest
@testable import WalnutAgent

final class EngineInspectorTests: XCTestCase {
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
