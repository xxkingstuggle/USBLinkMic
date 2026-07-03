import Foundation
import os

/// 维护一段真实波形数据，用于 UI 绘制。
/// 按 10ms 窗口计算每个窗口的 (min, max) 样本值，并使用循环缓冲区避免 O(n) 移位。
/// 使用 os_unfair_lock 确保线程安全且无优先级反转。
final class WaveformData: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var data: [(Float, Float)]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int

    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
        self.data = Array(repeating: (0, 0), count: self.capacity)
    }

    /// 追加单声道 Float 样本。
    func append(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty, sampleRate > 0 else { return }
        // 与 Rust 原项目一致：10ms 窗口
        let windowSize = max(1, Int(sampleRate * 0.010))

        var windows: [(Float, Float)] = []
        var start = 0
        while start < samples.count {
            let end = Swift.min(start + windowSize, samples.count)
            var minVal: Float = 0
            var maxVal: Float = 0
            for index in start..<end {
                let s = samples[index]
                if s < minVal { minVal = s }
                if s > maxVal { maxVal = s }
            }
            windows.append((minVal, maxVal))
            start = end
        }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for window in windows {
            data[(head + count) % capacity] = window
            if count < capacity {
                count += 1
            } else {
                head = (head + 1) % capacity
            }
        }
    }

    func read() -> [(Float, Float)] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        var result: [(Float, Float)] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            result.append(data[(head + i) % capacity])
        }
        return result
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        head = 0
        count = 0
    }
}
