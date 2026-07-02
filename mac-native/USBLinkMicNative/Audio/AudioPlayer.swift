import Foundation
import AudioToolbox

/// 管理 Mac 端音频输出：把从手机传来的样本写入 ring buffer，再通过 AudioQueue 播放到指定设备。
/// 与 AVAudioEngine 方案不同，AudioQueue 可以设置 kAudioQueueProperty_CurrentDevice，
/// 只影响本队列使用的输出设备，不需要修改系统默认输出设备。
final class AudioPlayer: @unchecked Sendable {
    private var queue: AudioQueueRef?
    private var ringBuffer: SampleRingBuffer?

    private var sampleRate: Double = 44100
    private var channelCount: Int = 1
    private var bytesPerFrame: Int = 2

    var gain: Float = 1.0
    var isMuted: Bool = false

    // 预分配的读取缓冲区，避免 AudioQueue 回调线程实时堆分配。
    private var readBuffer: [Float] = []

    /// 启动播放器。
    func start(sampleRate: Double, channelCount: Int, outputDeviceID: AudioDeviceID?) throws {
        stop()

        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        // AudioQueue 输出固定为单声道 i16，ring buffer 也保存单声道 Float。
        self.bytesPerFrame = 2 * self.channelCount

        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: UInt32(self.channelCount),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        // ring buffer 容量按 1.5 秒计算（单声道 Float 样本）。
        let capacity = Int(sampleRate * 1.5)
        let ring = SampleRingBuffer(capacity: max(capacity, 8192))
        self.ringBuffer = ring

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var newQueue: AudioQueueRef?
        let createStatus = AudioQueueNewOutput(&format, audioQueueOutputCallback, selfPtr, nil, nil, 0, &newQueue)
        guard createStatus == noErr, let newQueue = newQueue else {
            throw AudioPlayerError.engineStartFailed
        }

        // 指定输出设备：AudioQueue 级别只影响本队列，不影响系统默认设备。
        if let deviceID = outputDeviceID {
            var id = deviceID
            let size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let setStatus = AudioQueueSetProperty(newQueue, kAudioQueueProperty_CurrentDevice, &id, size)
            if setStatus != noErr {
                AudioQueueDispose(newQueue, true)
                throw AudioPlayerError.setDeviceFailed(setStatus)
            }
        }

        // 分配 3 个 50ms 的 buffer。
        let bufferSize = UInt32(bytesPerFrame * Int(sampleRate) / 20)
        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            let allocStatus = AudioQueueAllocateBuffer(newQueue, bufferSize, &buffer)
            guard allocStatus == noErr, let buffer = buffer else { continue }
            fillAndEnqueue(buffer: buffer, queue: newQueue)
        }

        let startStatus = AudioQueueStart(newQueue, nil)
        guard startStatus == noErr else {
            AudioQueueDispose(newQueue, true)
            throw AudioPlayerError.engineStartFailed
        }

        self.queue = newQueue
    }

    func stop() {
        if let queue = queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
        }
        queue = nil
        ringBuffer?.reset()
    }

    /// 写入音频包数据。可在任意线程调用。
    @discardableResult
    func write(packet: AudioPacketMessage) -> [Float] {
        guard let format = AudioSampleFormat(rawValue: packet.audioFormat) else { return [] }
        let mono = format.interleavedBytesToMonoFloat(packet.buffer, channelCount: Int(packet.channelCount))

        // 更新内部采样率（如果后续包变化）。
        sampleRate = Double(packet.sampleRate)
        channelCount = max(1, Int(packet.channelCount))
        bytesPerFrame = 2 * channelCount

        ringBuffer?.write(mono)
        return mono
    }

    fileprivate func fillAndEnqueue(buffer: AudioQueueBufferRef, queue: AudioQueueRef? = nil) {
        let q = queue ?? self.queue
        guard q != nil else { return }

        let frames = Int(buffer.pointee.mAudioDataBytesCapacity) / max(1, bytesPerFrame)
        let needed = frames
        if readBuffer.count < needed {
            readBuffer = Array(repeating: Float(0), count: needed)
        }

        let readCount = ringBuffer?.read(into: &readBuffer, count: needed) ?? 0

        let gain = self.gain
        let muted = self.isMuted
        let ptr = buffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self)
        let maxVal = Float(Int16.max)

        for frame in 0..<frames {
            let sample = muted ? 0 : readBuffer[frame] * gain
            let clamped = max(-1.0, min(1.0, sample))
            let value = Int16(clamped * maxVal)
            // 将单声道复制到所有输出通道（交错格式）。
            for ch in 0..<max(1, channelCount) {
                ptr[frame * max(1, channelCount) + ch] = value
            }
        }

        buffer.pointee.mAudioDataByteSize = UInt32(frames * max(1, bytesPerFrame))
        AudioQueueEnqueueBuffer(q!, buffer, 0, nil)
    }
}

private func audioQueueOutputCallback(userData: UnsafeMutableRawPointer?, queue: AudioQueueRef, buffer: AudioQueueBufferRef) {
    guard let userData = userData else { return }
    let player = Unmanaged<AudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    player.fillAndEnqueue(buffer: buffer, queue: queue)
}

enum AudioPlayerError: Error {
    case badFormat
    case engineStartFailed
    case setDeviceFailed(OSStatus)

    var localizedDescription: String {
        switch self {
        case .badFormat:
            return "音频格式无效"
        case .engineStartFailed:
            return "音频播放器启动失败"
        case .setDeviceFailed(let status):
            return "无法设置音频输出设备 (OSStatus: \(status))"
        }
    }
}
