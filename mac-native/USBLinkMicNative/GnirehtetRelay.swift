import Foundation
import Darwin

@MainActor
final class GnirehtetRelay {
    private var process: Process?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(port: Int) async throws {
        guard (1...65_535).contains(port) else {
            throw GnirehtetRelayError.invalidPort
        }
        if isRunning { return }

        guard let executableURL = Bundle.main.url(forResource: "gnirehtet-relay", withExtension: nil) else {
            throw GnirehtetRelayError.helperMissing
        }

        let relayProcess = Process()
        relayProcess.executableURL = executableURL
        relayProcess.arguments = ["relay", "-p", String(port)]
        // The relay may run for days. Sending its output to /dev/null avoids an undrained Pipe
        // filling up and stalling packet forwarding.
        relayProcess.standardOutput = FileHandle.nullDevice
        relayProcess.standardError = FileHandle.nullDevice

        try relayProcess.run()
        process = relayProcess

        for _ in 0..<40 {
            guard relayProcess.isRunning else {
                process = nil
                throw GnirehtetRelayError.exited(relayProcess.terminationStatus)
            }
            if await Task.detached(priority: .utility, operation: {
                Self.canConnect(to: port)
            }).value {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        stop()
        throw GnirehtetRelayError.notReady
    }

    func stop() {
        guard let relayProcess = process else { return }
        process = nil
        if relayProcess.isRunning {
            relayProcess.terminate()
        }
    }

    nonisolated private static func canConnect(to port: Int) -> Bool {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { Darwin.close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(
                    socketFD,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
    }
}

enum GnirehtetRelayError: LocalizedError {
    case invalidPort
    case helperMissing
    case exited(Int32)
    case notReady

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Relay 端口无效"
        case .helperMissing:
            return "应用包中缺少 gnirehtet relay"
        case .exited(let status):
            return "gnirehtet relay 启动后退出（状态码 \(status)）"
        case .notReady:
            return "gnirehtet relay 未能监听端口"
        }
    }
}
