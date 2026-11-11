import Darwin
import Foundation
import XCTest
@testable import WalnutAgent

final class CLILineReaderTests: XCTestCase {
    func testNonblockingInputWaitsForTheNextFrame() throws {
        let pipe = Pipe()
        let input = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(input, F_GETFL)
        XCTAssertEqual(fcntl(input, F_SETFL, flags | O_NONBLOCK), 0)
        let writer = pipe.fileHandleForWriting
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) {
            try? writer.write(contentsOf: Data("next\n".utf8))
            try? writer.close()
        }
        let reader = CLILineReader(descriptor: input)
        XCTAssertEqual(try reader.next()?.get(), Data("next".utf8))
        XCTAssertNil(try reader.next())
    }

    func testReadsFramesAndDiscardsOversizedLine() throws {
        let exact = Data(repeating: 0x61, count: DeviceBridge.requestLimit)
        var bytes = Data([0x0A])
        bytes.append(exact)
        bytes.append(0x0A)
        bytes.append(exact)
        bytes.append(contentsOf: [0x0D, 0x0A])
        bytes.append(exact)
        bytes.append(contentsOf: [0x61, 0x0A])
        bytes.append(contentsOf: [0xFF, 0x0D, 0x0A])
        bytes.append(Data("last".utf8))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let reader = CLILineReader(descriptor: input.fileDescriptor)

        XCTAssertEqual(try reader.next()?.get(), Data())
        XCTAssertEqual(try reader.next()?.get(), exact)
        XCTAssertEqual(try reader.next()?.get(), exact)
        XCTAssertThrowsError(try reader.next()?.get()) { error in
            XCTAssertEqual(error.localizedDescription, "The session request exceeds 256 KiB.")
        }
        XCTAssertEqual(try reader.next()?.get(), Data([0xFF]))
        XCTAssertEqual(try reader.next()?.get(), Data("last".utf8))
        XCTAssertNil(try reader.next())
    }
}
