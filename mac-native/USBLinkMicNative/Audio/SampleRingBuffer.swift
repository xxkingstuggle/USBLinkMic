import Foundation
import AVFoundation

/// 简单的线程安全环形缓冲区，用于存储音频样本（Float）。
/// 写入和读取分别发生在不同线程：写入在 MicReceiver 的队列，读取在 AVAudioEngine 的渲染线程。
final class SampleRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var available: Int = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(capacity, 1024)
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
    }

    deinit {
        buffer.deallocate()
    }

    /// 写入样本，若缓冲区满则覆盖最旧数据。
    func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            if available < capacity {
                available += 1
            } else {
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    /// 读取最多 count 个样本到 dst，返回实际读取数。不足时用 silence 填充。
    func read(into dst: inout [Float], count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let toRead = min(count, available)
        for i in 0..<toRead {
            dst[i] = buffer[(readIndex + i) % capacity]
        }
        for i in toRead..<count {
            dst[i] = 0
        }
        readIndex = (readIndex + toRead) % capacity
        available -= toRead
        return toRead
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        readIndex = 0
        available = 0
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return available
    }
}
