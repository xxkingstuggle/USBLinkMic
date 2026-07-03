import Foundation
import AVFoundation
import os

/// 线程安全环形缓冲区，按块拷贝写入/读取单声道 Float 样本。
/// 写入发生在 MicReceiver 的 DispatchQueue，读取发生在 AVAudioEngine 的渲染线程。
/// 使用 os_unfair_lock 避免 NSLock 在实时音频线程上的优先级反转风险。
final class SampleRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var available: Int = 0
    private var lock = os_unfair_lock_s()

    init(capacity: Int) {
        self.capacity = max(capacity, 1024)
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
    }

    deinit {
        buffer.deallocate()
    }

    /// 写入样本。若缓冲区满，覆盖最旧数据。持有锁一次完成块拷贝。
    func write(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let count = samples.count

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let writable = min(count, capacity)
        var srcOffset = count - writable
        var dstOffset = writeIndex

        // 第一个块：从当前写指针到缓冲区末尾
        let firstChunk = min(writable, capacity - dstOffset)
        if firstChunk > 0 {
            samples.withUnsafeBufferPointer { src in
                buffer.advanced(by: dstOffset).update(from: src.baseAddress!.advanced(by: srcOffset), count: firstChunk)
            }
            srcOffset += firstChunk
            dstOffset = (dstOffset + firstChunk) % capacity
        }

        // 第二个块：绕回到缓冲区开头
        let secondChunk = writable - firstChunk
        if secondChunk > 0 {
            samples.withUnsafeBufferPointer { src in
                buffer.advanced(by: dstOffset).update(from: src.baseAddress!.advanced(by: srcOffset), count: secondChunk)
            }
            dstOffset = (dstOffset + secondChunk) % capacity
        }

        writeIndex = dstOffset
        available += writable
        if available > capacity {
            // 覆盖旧数据，读指针前进
            readIndex = (readIndex + (available - capacity)) % capacity
            available = capacity
        }
    }

    /// 读取最多 count 个样本到 dst，返回实际读取数。不足时用 silence 填充。持有锁一次完成块拷贝。
    func read(into dst: inout [Float], count: Int) -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let toRead = min(count, available)
        var dstOffset = 0
        var srcOffset = readIndex

        // 第一个块：从读指针到缓冲区末尾
        let firstChunk = min(toRead, capacity - srcOffset)
        if firstChunk > 0 {
            dst.withUnsafeMutableBufferPointer { dstPtr in
                dstPtr.baseAddress!.update(from: buffer.advanced(by: srcOffset), count: firstChunk)
            }
            dstOffset += firstChunk
            srcOffset = (srcOffset + firstChunk) % capacity
        }

        // 第二个块：绕回到缓冲区开头
        let secondChunk = toRead - firstChunk
        if secondChunk > 0 {
            dst.withUnsafeMutableBufferPointer { dstPtr in
                dstPtr.baseAddress!.advanced(by: dstOffset).update(from: buffer.advanced(by: srcOffset), count: secondChunk)
            }
            dstOffset += secondChunk
        }

        // 剩余未读取部分填充静音
        for i in dstOffset..<count {
            dst[i] = 0
        }

        readIndex = (readIndex + toRead) % capacity
        available -= toRead
        return toRead
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        writeIndex = 0
        readIndex = 0
        available = 0
    }

    var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return available
    }
}
