import Foundation

/// 维护一段真实波形数据，用于 UI 绘制。
/// 按低延迟窗口计算每个窗口的 (min, max) 样本值。
final class WaveformData: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [(Float, Float)] = []
    private let capacity: Int

    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    /// 追加单声道 Float 样本。
    func append(samples: [Float], sampleRate: Double) {
        guard samples.count > 0, sampleRate > 0 else { return }
        let windowSize = max(1, Int(sampleRate * 0.005))  // 5ms

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

        lock.lock()
        defer { lock.unlock() }
        data.append(contentsOf: windows)
        if data.count > capacity {
            data.removeFirst(data.count - capacity)
        }
    }

    func read() -> [(Float, Float)] {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        data.removeAll()
    }
}
