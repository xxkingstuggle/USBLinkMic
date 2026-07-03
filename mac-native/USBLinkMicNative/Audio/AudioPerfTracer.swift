import Foundation
import Darwin
import os

/// 极低开销性能追踪器，用于诊断音频热路径的 CPU 消耗。
/// 使用 mach_absolute_time 避免系统调用开销，聚合后通过 os_log 输出到 Console.app。
final class AudioPerfTracer: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var records: [String: Record] = [:]
    private var reportCounter: Int = 0
    private let reportInterval = 100  // 每 100 次采样输出一次
    private let maxLogFileSize: UInt64 = 512 * 1024  // 512 KB 上限
    private let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("usblinkmic_perf.log")

    private struct Record {
        var totalNanos: UInt64 = 0
        var maxNanos: UInt64 = 0
        var count: Int = 0
        var overruns: Int = 0
    }

    private let log = OSLog(subsystem: "com.zjx.USBLinkMic", category: "Perf")

    /// 记录一次计时样本。
    func record(_ name: String, nanos: UInt64, overrun: Bool = false) {
        os_unfair_lock_lock(&lock)
        var r = records[name] ?? Record()
        r.totalNanos += nanos
        r.maxNanos = max(r.maxNanos, nanos)
        r.count += 1
        if overrun { r.overruns += 1 }
        records[name] = r

        reportCounter += 1
        if reportCounter >= reportInterval {
            reportCounter = 0
            flush()
        }
        os_unfair_lock_unlock(&lock)
    }

    private func flush() {
        guard !records.isEmpty else { return }
        let sorted = records.sorted { $0.value.totalNanos > $1.value.totalNanos }
        var lines: [String] = []
        for (name, r) in sorted {
            let avgUs = Double(r.totalNanos) / Double(max(r.count, 1)) / 1000.0
            let maxUs = Double(r.maxNanos) / 1000.0
            let pct = Double(r.totalNanos) / 1_000_000.0
            let line = "[Perf] \(name): count=\(r.count) total=\(String(format: "%.1f", pct))ms avg=\(String(format: "%.1f", avgUs))us max=\(String(format: "%.1f", maxUs))us"
            lines.append(line)
            os_log(.default, log: log, "%{public}s", line)
        }
        let report = lines.joined(separator: "\n") + "\n---\n"
        if let data = report.data(using: .utf8) {
            // 限制日志文件大小，防止长期运行无限制增长。
            if let fh = try? FileHandle(forWritingTo: tempURL) {
                let currentSize = try? fh.seekToEnd()
                if let currentSize, currentSize > maxLogFileSize {
                    // 截断：只保留后半部分
                    let keepSize = maxLogFileSize / 2
                    fh.closeFile()
                    if let existing = try? Data(contentsOf: tempURL), existing.count > keepSize {
                        let trimmed = existing.suffix(Int(keepSize))
                        try? trimmed.write(to: tempURL)
                    }
                }
                if let fh = try? FileHandle(forWritingTo: tempURL) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? report.write(to: tempURL, atomically: false, encoding: .utf8)
            }
        }
        records.removeAll()
    }
}

/// 获取纳秒时间戳。CLOCK_MONOTONIC_RAW 不受系统时间调整影响。
func perfNow() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
}

/// 全局单例，供各模块共享。
let sharedPerfTracer = AudioPerfTracer()

/// 辅助宏式调用：生成一个 timing guard，在 block 结束后自动记录。
/// 用法：
///   perfTrack("render") { ... }
func perfTrack<T>(_ tracer: AudioPerfTracer, _ name: String, _ block: () throws -> T) rethrows -> T {
    let start = perfNow()
    let result = try block()
    let elapsed = perfNow() - start
    tracer.record(name, nanos: elapsed)
    return result
}
