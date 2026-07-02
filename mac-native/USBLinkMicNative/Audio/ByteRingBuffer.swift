import Foundation

/// 线程安全字节环形缓冲区，模仿 Rust 原项目中的 rtrb（Ring Buffer）。
/// 写入端为网络接收线程，读取端为音频渲染线程。
final class ByteRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<UInt8>
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var available: Int = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(capacity, 1024)
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.capacity)
    }

    deinit {
        buffer.deallocate()
    }

    /// 写入字节。若缓冲区满，覆盖最旧数据。返回实际写入字节数。
    func write(_ data: Data) -> Int {
        let count = data.count
        guard count > 0 else { return 0 }

        lock.lock()
        defer { lock.unlock() }

        let writable = min(count, capacity)
        var srcOffset = 0
        var dstOffset = writeIndex

        let firstChunk = min(writable, capacity - dstOffset)
        if firstChunk > 0 {
            data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: UInt8.self).baseAddress!
                buffer.advanced(by: dstOffset).update(from: src.advanced(by: srcOffset), count: firstChunk)
            }
            srcOffset += firstChunk
            dstOffset = (dstOffset + firstChunk) % capacity
        }

        let secondChunk = writable - firstChunk
        if secondChunk > 0 {
            data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: UInt8.self).baseAddress!
                buffer.advanced(by: dstOffset).update(from: src.advanced(by: srcOffset), count: secondChunk)
            }
            dstOffset = (dstOffset + secondChunk) % capacity
        }

        writeIndex = dstOffset
        available += writable
        if available > capacity {
            readIndex = (readIndex + (available - capacity)) % capacity
            available = capacity
        }
        return writable
    }

    /// 读取最多 count 个字节到 dst。count 会被向下对齐到 frameBytes 的整数倍。
    /// 返回实际读取的字节数（已对齐）。
    func read(into dst: inout [UInt8], count: Int, frameBytes: Int) -> Int {
        let alignedCount = max(0, count - (count % max(1, frameBytes)))
        guard alignedCount > 0 else { return 0 }

        lock.lock()
        defer { lock.unlock() }

        let toRead = min(alignedCount, available)
        var dstOffset = 0
        var srcOffset = readIndex

        let firstChunk = min(toRead, capacity - srcOffset)
        if firstChunk > 0 {
            dst.withUnsafeMutableBufferPointer { dstPtr in
                dstPtr.baseAddress!.update(from: buffer.advanced(by: srcOffset), count: firstChunk)
            }
            dstOffset += firstChunk
            srcOffset = (srcOffset + firstChunk) % capacity
        }

        let secondChunk = toRead - firstChunk
        if secondChunk > 0 {
            dst.withUnsafeMutableBufferPointer { dstPtr in
                dstPtr.baseAddress!.advanced(by: dstOffset).update(from: buffer.advanced(by: srcOffset), count: secondChunk)
            }
            dstOffset += secondChunk
        }

        for i in dstOffset..<alignedCount {
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
