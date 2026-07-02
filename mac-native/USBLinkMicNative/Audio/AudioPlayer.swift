import Foundation
import AudioToolbox

/// 管理 Mac 端音频输出：直接创建 AudioUnit HAL Output 到指定设备，
/// 输出格式跟随用户配置（i16/i32/f32/u8，i24 映射为 f32），音频数据以原始字节存入 ring buffer。
/// 与 Rust 原项目 cpal 方案完全对应：
///   - 枚举设备并保存设备 ID
///   - 创建 stream 时指定设备
///   - 回调从字节 ring buffer 读取并按格式解码到输出缓冲区
final class AudioPlayer: @unchecked Sendable {
    private var audioUnit: AudioUnit?
    private var ringBuffer: ByteRingBuffer?

    private var sampleRate: Double = 44100
    private var channelCount: Int = 1
    private var audioFormat: AudioSampleFormat = .i16
    private var frameBytes: Int = 2

    var gain: Float = 1.0
    var isMuted: Bool = false

    // 预分配的读取缓冲区，避免渲染线程实时堆分配。
    private var readBuffer: [UInt8] = []

    /// 启动播放器。
    func start(
        sampleRate: Double,
        channelCount: Int,
        audioFormat: AudioSampleFormat,
        outputDeviceID: AudioDeviceID?
    ) throws {
        stop()

        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        self.audioFormat = audioFormat
        self.frameBytes = audioFormat.sampleSize * self.channelCount

        // 创建 HAL Output AudioUnit（对应 cpal 在 macOS 上的底层实现）。
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw AudioPlayerError.engineStartFailed
        }

        var unit: AudioUnit?
        let createStatus = AudioComponentInstanceNew(component, &unit)
        guard createStatus == noErr, let unit = unit else {
            throw AudioPlayerError.engineStartFailed
        }

        // 指定输出设备：只影响本 AudioUnit，不影响系统默认设备。
        if let deviceID = outputDeviceID {
            var id = deviceID
            let size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let setStatus = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                size
            )
            if setStatus != noErr {
                AudioComponentInstanceDispose(unit)
                throw AudioPlayerError.setDeviceFailed(setStatus)
            }
        }

        // 设置输出格式：与 Rust 原项目一致，i24 映射为 f32。
        let outputASBD = asbd(sampleRate: sampleRate, channels: self.channelCount, format: audioFormat)
        var streamFormat = outputASBD
        let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &streamFormat,
            formatSize
        )
        if formatStatus != noErr {
            AudioComponentInstanceDispose(unit)
            throw AudioPlayerError.unsupportedFormat(formatStatus)
        }

        // 设置渲染回调。
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var callback = AURenderCallbackStruct(inputProc: audioUnitRenderCallback, inputProcRefCon: selfPtr)
        let callbackStatus = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        if callbackStatus != noErr {
            AudioComponentInstanceDispose(unit)
            throw AudioPlayerError.engineStartFailed
        }

        let initStatus = AudioUnitInitialize(unit)
        if initStatus != noErr {
            AudioComponentInstanceDispose(unit)
            throw AudioPlayerError.engineStartFailed
        }

        let startStatus = AudioOutputUnitStart(unit)
        if startStatus != noErr {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw AudioPlayerError.engineStartFailed
        }

        // ring buffer 容量按 1 秒计算（原始字节）。
        let capacity = Int(sampleRate) * frameBytes
        self.ringBuffer = ByteRingBuffer(capacity: max(capacity, 4096))
        self.audioUnit = unit
    }

    func stop() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        audioUnit = nil
        ringBuffer?.reset()
    }

    /// 写入音频包原始字节。可在任意线程调用。
    func write(packet: AudioPacketMessage) {
        sampleRate = Double(packet.sampleRate)
        channelCount = max(1, Int(packet.channelCount))
        if let format = AudioSampleFormat(rawValue: packet.audioFormat) {
            audioFormat = format
        }
        frameBytes = audioFormat.sampleSize * channelCount
        _ = ringBuffer?.write(packet.buffer)
    }

    fileprivate func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
        timeStamp: UnsafePointer<AudioTimeStamp>?,
        frameCount: UInt32,
        outputData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let abl = outputData,
              let buffer = abl.pointee.mBuffers.mData,
              let ringBuffer = ringBuffer else { return noErr }

        let frames = Int(frameCount)
        let neededBytes = frames * frameBytes
        if readBuffer.count < neededBytes {
            readBuffer = Array(repeating: UInt8(0), count: neededBytes)
        }

        let readBytes = ringBuffer.read(into: &readBuffer, count: neededBytes, frameBytes: frameBytes)

        // 按格式解码字节到输出缓冲区。i24 以 f32 输出。
        switch audioFormat {
        case .u8:
            decodeU8(buffer: buffer, bytes: readBuffer, readBytes: readBytes, frames: frames)
        case .i16:
            decodeI16(buffer: buffer, bytes: readBuffer, readBytes: readBytes, frames: frames)
        case .i24:
            decodeI24AsF32(buffer: buffer, bytes: readBuffer, readBytes: readBytes, frames: frames)
        case .i32:
            decodeI32(buffer: buffer, bytes: readBuffer, readBytes: readBytes, frames: frames)
        case .f32:
            decodeF32(buffer: buffer, bytes: readBuffer, readBytes: readBytes, frames: frames)
        }

        return noErr
    }

    // MARK: - 解码辅助

    private func decodeU8(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let ptr = buffer.assumingMemoryBound(to: UInt8.self)
        for frame in 0..<frames {
            for ch in 0..<channelCount {
                let sample: UInt8
                if frame * frameBytes + ch < readBytes {
                    let raw = bytes[frame * frameBytes + ch]
                    let floatValue = isMuted ? 0.0 : (Float(Int16(raw) - 128) / 128.0) * gain
                    let clamped = max(-1.0, min(1.0, floatValue))
                    sample = UInt8(clamped * 128.0 + 128.0)
                } else {
                    sample = 128
                }
                ptr[frame * channelCount + ch] = sample
            }
        }
    }

    private func decodeI16(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let ptr = buffer.assumingMemoryBound(to: Int16.self)
        for frame in 0..<frames {
            for ch in 0..<channelCount {
                let sample: Int16
                if (frame * frameBytes + ch * 2 + 1) < readBytes {
                    let idx = frame * frameBytes + ch * 2
                    let raw = Int16(bytes[idx]) | (Int16(bytes[idx + 1]) << 8)
                    let floatValue = isMuted ? 0.0 : (Float(raw) / Float(Int16.max)) * gain
                    let clamped = max(-1.0, min(1.0, floatValue))
                    sample = Int16(clamped * Float(Int16.max))
                } else {
                    sample = 0
                }
                ptr[frame * channelCount + ch] = sample
            }
        }
    }

    private func decodeI24AsF32(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let ptr = buffer.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            for ch in 0..<channelCount {
                let sample: Float
                if (frame * frameBytes + ch * 3 + 2) < readBytes {
                    let idx = frame * frameBytes + ch * 3
                    let b0 = Int32(bytes[idx])
                    let b1 = Int32(bytes[idx + 1])
                    let b2 = Int32(bytes[idx + 2])
                    var value = (b0 << 8) | (b1 << 16) | (b2 << 24)
                    value >>= 8
                    sample = isMuted ? 0.0 : (Float(value) / Float(1 << 23)) * gain
                } else {
                    sample = 0.0
                }
                ptr[frame * channelCount + ch] = sample
            }
        }
    }

    private func decodeI32(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let ptr = buffer.assumingMemoryBound(to: Int32.self)
        for frame in 0..<frames {
            for ch in 0..<channelCount {
                let sample: Int32
                if (frame * frameBytes + ch * 4 + 3) < readBytes {
                    let idx = frame * frameBytes + ch * 4
                    let raw = Int32(bytes[idx])
                        | (Int32(bytes[idx + 1]) << 8)
                        | (Int32(bytes[idx + 2]) << 16)
                        | (Int32(bytes[idx + 3]) << 24)
                    let floatValue = isMuted ? 0.0 : (Float(raw) / Float(Int32.max)) * gain
                    let clamped = max(-1.0, min(1.0, floatValue))
                    sample = Int32(clamped * Float(Int32.max))
                } else {
                    sample = 0
                }
                ptr[frame * channelCount + ch] = sample
            }
        }
    }

    private func decodeF32(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let ptr = buffer.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            for ch in 0..<channelCount {
                let sample: Float
                if (frame * frameBytes + ch * 4 + 3) < readBytes {
                    let idx = frame * frameBytes + ch * 4
                    var value: UInt32 = 0
                    value |= UInt32(bytes[idx])
                    value |= UInt32(bytes[idx + 1]) << 8
                    value |= UInt32(bytes[idx + 2]) << 16
                    value |= UInt32(bytes[idx + 3]) << 24
                    var rawFloat: Float = 0
                    memcpy(&rawFloat, &value, 4)
                    sample = isMuted ? 0.0 : rawFloat * gain
                } else {
                    sample = 0.0
                }
                ptr[frame * channelCount + ch] = sample
            }
        }
    }
}

private let audioUnitRenderCallback: AURenderCallback = { inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData in
    let player = Unmanaged<AudioPlayer>.fromOpaque(inRefCon).takeUnretainedValue()
    return player.render(actionFlags: ioActionFlags, timeStamp: inTimeStamp, frameCount: inNumberFrames, outputData: ioData)
}

private func asbd(sampleRate: Double, channels: Int, format: AudioSampleFormat) -> AudioStreamBasicDescription {
    switch format {
    case .u8:
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 8,
            mReserved: 0
        )
    case .i16:
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )
    case .i24:
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
    case .i32:
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
    case .f32:
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }
}

enum AudioPlayerError: Error {
    case badFormat
    case engineStartFailed
    case setDeviceFailed(OSStatus)
    case unsupportedFormat(OSStatus)

    var localizedDescription: String {
        switch self {
        case .badFormat:
            return "音频格式无效"
        case .engineStartFailed:
            return "音频播放器启动失败"
        case .setDeviceFailed(let status):
            return "无法设置音频输出设备 (OSStatus: \(status))"
        case .unsupportedFormat(let status):
            return "设备不支持该音频格式 (OSStatus: \(status))"
        }
    }
}
