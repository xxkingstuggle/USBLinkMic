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
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { process in
                let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: ShellResult(status: process.terminationStatus, output: output, error: error))
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + timeout,
                    execute: timeoutWork
                )
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: ShellResult(status: -1, output: "", error: error.localizedDescription))
            }
        }
    }

    static func runPath(_ command: String, _ arguments: [String], timeout: TimeInterval = 10) async -> ShellResult {
        await run("/usr/bin/env", [command] + arguments, timeout: timeout)
    }
}
