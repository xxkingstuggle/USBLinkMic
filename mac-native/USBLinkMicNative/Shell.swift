import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let output: String
    let error: String

    var mergedOutput: String {
        [output, error].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
    }
}

enum Shell {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    let deadline = Date().addingTimeInterval(timeout)
                    while process.isRunning && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    if process.isRunning {
                        process.terminate()
                    }
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: ShellResult(status: -1, output: "", error: error.localizedDescription))
                    return
                }

                let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: ShellResult(status: process.terminationStatus, output: output, error: error))
            }
        }
    }

    static func runPath(_ command: String, _ arguments: [String], timeout: TimeInterval = 10) async -> ShellResult {
        await run("/usr/bin/env", [command] + arguments, timeout: timeout)
    }
}
