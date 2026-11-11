import Darwin
import Foundation

final class CLILineReader {
    private let descriptor: Int32
    private let limit: Int
    private let oversizedError: AgentError
    private var buffer = [UInt8](repeating: 0, count: 8 * 1024)
    private var unread = 0..<0

    init(
        descriptor: Int32 = STDIN_FILENO,
        limit: Int = DeviceBridge.requestLimit,
        oversizedError: AgentError = AgentError("The session request exceeds 256 KiB.")
    ) {
        self.descriptor = descriptor
        self.limit = limit
        self.oversizedError = oversizedError
    }

    func next() throws -> Result<Data, AgentError>? {
        var frame = Data()
        var oversized = false
        while true {
            if unread.isEmpty { try refill() }
            if unread.isEmpty {
                if oversized || frame.count > limit { return .failure(oversizedError) }
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
                return oversized || frame.count > limit ? .failure(oversizedError) : .success(frame)
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
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK {
                // An inspector terminal may share the input and output descriptor's nonblocking flag.
                var readable = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                if poll(&readable, 1, -1) >= 0 || errno == EINTR { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }
}
