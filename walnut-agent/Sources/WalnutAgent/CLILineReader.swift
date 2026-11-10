import Darwin
import Foundation

final class CLILineReader {
    private static let oversized = AgentError("The session request exceeds 256 KiB.")
    private let descriptor: Int32
    private var buffer = [UInt8](repeating: 0, count: 8 * 1024)
    private var unread = 0..<0

    init(descriptor: Int32 = STDIN_FILENO) {
        self.descriptor = descriptor
    }

    func next() throws -> Result<Data, AgentError>? {
        let limit = DeviceBridge.requestLimit
        var frame = Data()
        var oversized = false
        while true {
            if unread.isEmpty { try refill() }
            if unread.isEmpty {
                if oversized || frame.count > limit { return .failure(Self.oversized) }
                return frame.isEmpty ? nil : .success(frame)
            }

            let newline = buffer[unread].firstIndex(of: 0x0A)
            let end = newline ?? unread.upperBound
            if !oversized {
                // Allow room for the optional CR in a CRLF delimiter.
                if frame.count + end - unread.lowerBound <= limit + 1 {
                    frame.append(contentsOf: buffer[unread.lowerBound..<end])
                } else {
                    oversized = true
                    frame = Data()
                }
            }
            unread = (newline == nil ? end : end + 1)..<unread.upperBound
            if newline != nil {
                if frame.last == 0x0D { frame.removeLast() }
                return oversized || frame.count > limit ? .failure(Self.oversized) : .success(frame)
            }
        }
    }

    private func refill() throws {
        let capacity = buffer.count
        while true {
            let count = Darwin.read(descriptor, &buffer, capacity)
            if count >= 0 {
                unread = 0..<count
                return
            }
            let code = errno
            if code != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
        }
    }
}
