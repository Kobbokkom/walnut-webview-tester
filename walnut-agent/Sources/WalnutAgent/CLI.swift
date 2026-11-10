import Darwin
import Foundation

@main
enum CLI {
    static let version = "0.1.1"

    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            switch arguments.first {
            case "pair" where arguments.count == 1:
                var buffer = [CChar](repeating: 0, count: 1025)
                guard readpassphrase("Walnut pairing token: ", &buffer, buffer.count, RPP_REQUIRE_TTY) != nil else {
                    throw AgentError("Run `walnut-agent pair` from a terminal and paste the token shown in Walnut.")
                }
                let pairing = try Pairing.fromToken(String(cString: buffer))
                try pairing.save(to: Pairing.file)
                print("Saved Walnut pairing.")
            case "session", "mcp":
                let bridge = DeviceBridge(usb: try parseUSB(Array(arguments.dropFirst())))
                let call: AgentToolCall = { name, arguments in try await bridge.call(name, arguments: arguments) }
                var succeeded = true
                do {
                    if arguments.first == "session" {
                        succeeded = try await CLISession(call: call).run()
                    } else {
                        try await MCPServer(call: call).run()
                    }
                } catch {
                    await bridge.shutdown()
                    throw error
                }
                await bridge.shutdown()
                if !succeeded { exit(EXIT_FAILURE) }
            case "--version" where arguments.count == 1:
                FileHandle.standardOutput.write(Data("\(version)\n".utf8))
            case "update" where arguments.count == 1:
                try await CLIUpdate.run()
            case "--help", "-h", nil:
                print(usage)
            default:
                throw AgentError(usage)
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static let usage = """
    Usage:
      walnut-agent --version
      walnut-agent update
      walnut-agent pair
      walnut-agent session [--usb [--local-port PORT] [--udid UDID]]
      walnut-agent mcp [--usb [--local-port PORT] [--udid UDID]]

    In a session, send one JSON request per line on stdin. Start with {"op":"tools"}.
    """

    static func parseUSB(_ arguments: [String]) throws -> USBOptions? {
        guard !arguments.isEmpty else { return nil }
        guard arguments.first == "--usb" else { throw AgentError(usage) }
        var options = USBOptions()
        var rest = arguments.dropFirst()
        while let option = rest.popFirst() {
            guard let value = rest.popFirst(), !value.isEmpty else { throw AgentError(usage) }
            switch option {
            case "--local-port" where options.localPort == nil:
                guard let port = UInt16(value), port > 0 else { throw AgentError("Invalid USB port.") }
                options.localPort = port
            case "--udid" where options.udid == nil:
                guard value.utf8.count <= 64, value.utf8.allSatisfy({ byte in
                    (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) ||
                    (0x61...0x66).contains(byte) || byte == 0x2D
                }) else { throw AgentError("Invalid iPhone UDID.") }
                options.udid = value
            default:
                throw AgentError(usage)
            }
        }
        return options
    }
}
