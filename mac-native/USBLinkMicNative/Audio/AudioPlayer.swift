import Foundation
import AudioToolbox
import Accelerate
import os

/// 管理 Mac 端音频输出：直接创建 AudioUnit HAL Output 到指定设备，
/// 输出格式跟随用户配置（i16/i32/f32/u8，i24 映射为 f32），音频数据以原始字节存入 ring buffer。
/// 与 Rust 原项目 cpal 方案完全对应：
///   - 枚举设备并保存设备 ID
///   - 创建 stream 时指定设备
///   - 回调从字节 ring buffer 读取并按格式解码到输出缓冲区
///
/// 解码使用 Accelerate/vDSP 向量化运算，避免实时音频线程上的逐样本 Swift 循环。
final class AudioPlayer: @unchecked Sendable {
    private var audioUnit: AudioUnit?
    private var ringBuffer: ByteRingBuffer?

    private var sampleRate: Double = 44100
    private var channelCount: Int = 1
    private var audioFormat: AudioSampleFormat = .i16
    private var frameBytes: Int = 2
    private var configurationLock = os_unfair_lock_s()

    private var gain: Float = 1.0
    private var isMuted: Bool = false

    // 预分配的缓冲区，避免渲染线程实时堆分配。
    private var readBuffer: [UInt8] = []
    /// 浮点工作区，供 vDSP 中间运算复用。
    private var floatWorkspace: [Float] = []
    /// i24 解包用 Int32 工作区。
    private var i32Workspace: [Int32] = []

    /// 启动播放器。
    func start(
        sampleRate: Double,
        channelCount: Int,
        audioFormat: AudioSampleFormat,
        gain: Float,
        isMuted: Bool,
        outputDeviceID: AudioDeviceID?
    ) throws {
        stop()
        os_unfair_lock_lock(&configurationLock)
        defer { os_unfair_lock_unlock(&configurationLock) }

        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        self.audioFormat = audioFormat
        self.frameBytes = audioFormat.sampleSize * self.channelCount
        self.gain = gain
        self.isMuted = isMuted

        let componentSubType: OSType = outputDeviceID == nil ? kAudioUnitSubType_DefaultOutput : kAudioUnitSubType_HALOutput

        // 系统默认输出使用 DefaultOutput；指定设备时使用 HALOutput，避免被系统默认输出路由固定住。
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: componentSubType,
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

            var currentID = AudioDeviceID()
            var currentSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let getStatus = AudioUnitGetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &currentID,
                &currentSize
            )
            NSLog("USB LinkMic AudioPlayer requested output device id=%u, current id=%u, getStatus=%d", deviceID, currentID, getStatus)
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

        var maximumFrames = UInt32(8192)
        var maximumFramesSize = UInt32(MemoryLayout<UInt32>.size)
        let maximumFramesStatus = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFrames,
            &maximumFramesSize
        )
        if maximumFramesStatus != noErr || maximumFrames == 0 {
            maximumFrames = 8192
        }

        // Allocate every render workspace before starting the AudioUnit. The callback must never
        // resize these buffers or observe a partially initialized player.
        let maxFramesPerRender = Int(maximumFrames)
        let capacity = Int(sampleRate) * frameBytes
        self.ringBuffer = ByteRingBuffer(capacity: max(capacity, 4096))
        self.readBuffer = Array(repeating: UInt8(0), count: maxFramesPerRender * self.frameBytes)
        self.floatWorkspace = Array(repeating: Float(0), count: maxFramesPerRender * self.channelCount)
        self.i32Workspace = Array(repeating: Int32(0), count: maxFramesPerRender * self.channelCount)

        let startStatus = AudioOutputUnitStart(unit)
        if startStatus != noErr {
            self.ringBuffer = nil
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw AudioPlayerError.engineStartFailed
        }
        self.audioUnit = unit
    }

    func stop() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        os_unfair_lock_lock(&configurationLock)
        audioUnit = nil
        let oldRingBuffer = ringBuffer
        ringBuffer = nil
        os_unfair_lock_unlock(&configurationLock)
        oldRingBuffer?.reset()
    }

    /// 写入音频包原始字节。可在任意线程调用。
    @discardableResult
    func write(packet: AudioPacketMessage) -> Bool {
        os_unfair_lock_lock(&configurationLock)
        let formatMatches = packet.sampleRate == UInt32(sampleRate.rounded()) &&
            packet.channelCount == UInt32(channelCount) &&
            packet.audioFormat == audioFormat.rawValue
        let targetRingBuffer = formatMatches ? ringBuffer : nil
        os_unfair_lock_unlock(&configurationLock)
        guard formatMatches else { return false }

        let t0 = perfNow()
        _ = targetRingBuffer?.write(packet.buffer)
        sharedPerfTracer.record("ringbuf.write", nanos: perfNow() - t0)
        return true
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
        guard readBuffer.count >= neededBytes else {
            let byteCount = Int(abl.pointee.mBuffers.mDataByteSize)
            buffer.initializeMemory(
                as: UInt8.self,
                repeating: audioFormat == .u8 ? 128 : 0,
                count: byteCount
            )
            return noErr
        }

        let t0 = perfNow()
        let readBytes = ringBuffer.read(into: &readBuffer, count: neededBytes, frameBytes: frameBytes)
        let t1 = perfNow()

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

        let t2 = perfNow()
        sharedPerfTracer.record("render.ringbuf_read", nanos: t1 - t0)
        sharedPerfTracer.record("render.decode", nanos: t2 - t1)

        return noErr
    }

    // MARK: - 工作区管理

    /// 确保浮点工作区至少有 `count` 个元素。
    private func ensureFloatWorkspace(_ count: Int) {
        if floatWorkspace.count < count {
            floatWorkspace = Array(repeating: 0, count: count)
        }
    }

    /// 确保 Int32 工作区至少有 `count` 个元素。
    private func ensureI32Workspace(_ count: Int) {
        if i32Workspace.count < count {
            i32Workspace = Array(repeating: 0, count: count)
        }
    }

    // MARK: - vDSP 解码

    /// 应用增益和静音到浮点缓冲区（就地操作，裸指针版本）。
    private func applyGainAndMute(_ ptr: UnsafeMutablePointer<Float>, count: Int) {
        let n = vDSP_Length(count)
        if isMuted {
            vDSP_vclr(ptr, 1, n)
        } else {
            var g = gain
            vDSP_vsmul(ptr, 1, &g, ptr, 1, n)
            var low: Float = -1.0
            var high: Float = 1.0
            vDSP_vclip(ptr, 1, &low, &high, ptr, 1, n)
        }
    }

    /// 应用增益和静音到浮点工作区（数组版本）。
    private func applyGainAndMute(_ samples: inout [Float], count: Int) {
        samples.withUnsafeMutableBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            applyGainAndMute(ptr, count: count)
        }
    }

    /// 零填充输出缓冲区从 `start` 位置开始。
    private func zeroFill<T: BinaryInteger>(_ ptr: UnsafeMutablePointer<T>, from start: Int, count: Int) {
        if start < count {
            ptr.advanced(by: start).initialize(repeating: 0, count: count - start)
        }
    }

    /// 零填充浮点输出缓冲区。
    private func zeroFillFloat(_ ptr: UnsafeMutablePointer<Float>, from start: Int, count: Int) {
        if start < count {
            vDSP_vclr(ptr.advanced(by: start), 1, vDSP_Length(count - start))
        }
    }

    // MARK: - U8 解码

    private func decodeU8(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let output = buffer.assumingMemoryBound(to: UInt8.self)
        let sampleCount = frames * channelCount
        ensureFloatWorkspace(sampleCount)
        let srcSamples = min(readBytes / (1 * channelCount), frames) * channelCount

        guard srcSamples > 0 else {
            output.initialize(repeating: 128, count: sampleCount)
            return
        }

        // vDSP 向量化：u8 → float [0,255] → [-1,1] → gain/clamp → [0,255] → u8
        if channelCount == 1 {
            bytes.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                let n = vDSP_Length(srcSamples)

                floatWorkspace.withUnsafeMutableBufferPointer { buf in
                    guard let ws = buf.baseAddress else { return }
                    // u8 → float [0, 255]
                    vDSP_vfltu8(src, 1, ws, 1, n)

                    // Map to [-1, 1]: (val / 128) - 1
                    var scale: Float = 1.0 / 128.0
                    var offset: Float = -1.0
                    vDSP_vsmsa(ws, 1, &scale, &offset, ws, 1, n)

                    // Gain + clamp
                    applyGainAndMute(ws, count: srcSamples)

                    // Map back to [0, 255]: val * 128 + 128
                    scale = 128.0
                    offset = 128.0
                    vDSP_vsmsa(ws, 1, &scale, &offset, ws, 1, n)

                    // Float → u8
                    vDSP_vfixu8(ws, 1, output, 1, n)
                }
            }
        } else {
            // 多声道：逐声道处理，利用 stride。
            let framesPerChannel = srcSamples / channelCount
            output.initialize(repeating: 128, count: sampleCount)

            bytes.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                for ch in 0..<channelCount {
                    let n = vDSP_Length(framesPerChannel)

                    floatWorkspace.withUnsafeMutableBufferPointer { buf in
                        guard let ws = buf.baseAddress else { return }
                        var scale: Float = 1.0 / 128.0
                        var offset: Float = -1.0

                        vDSP_vfltu8(src.advanced(by: ch), vDSP_Stride(channelCount), ws, 1, n)
                        vDSP_vsmsa(ws, 1, &scale, &offset, ws, 1, n)
                        applyGainAndMute(ws, count: framesPerChannel)
                        scale = 128.0
                        offset = 128.0
                        vDSP_vsmsa(ws, 1, &scale, &offset, ws, 1, n)
                        vDSP_vfixu8(ws, 1, output.advanced(by: ch), vDSP_Stride(channelCount), n)
                    }
                }
            }
        }
    }

    // MARK: - I16 解码

    private func decodeI16(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let output = buffer.assumingMemoryBound(to: Int16.self)
        let sampleCount = frames * channelCount
        ensureFloatWorkspace(sampleCount)
        let srcSamples = min(readBytes / (2 * channelCount), frames) * channelCount

        guard srcSamples > 0 else {
            output.initialize(repeating: 0, count: sampleCount)
            return
        }

        if channelCount == 1 {
            bytes.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
                let n = vDSP_Length(srcSamples)

                floatWorkspace.withUnsafeMutableBufferPointer { buf in
                    guard let ws = buf.baseAddress else { return }
                    // Int16 → normalized Float. vDSP_vflt16 itself does not normalize.
                    vDSP_vflt16(src, 1, ws, 1, n)
                    var normalize = Float(1.0 / 32768.0)
                    vDSP_vsmul(ws, 1, &normalize, ws, 1, n)
                    applyGainAndMute(ws, count: srcSamples)
                    var denormalize = Float(32767.0)
                    vDSP_vsmul(ws, 1, &denormalize, ws, 1, n)
                    vDSP_vfixr16(ws, 1, output, 1, n)
                }
            }
        } else {
            let framesPerChannel = srcSamples / channelCount
            output.initialize(repeating: 0, count: sampleCount)

            bytes.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
                for ch in 0..<channelCount {
                    let n = vDSP_Length(framesPerChannel)
                    floatWorkspace.withUnsafeMutableBufferPointer { buf in
                        guard let ws = buf.baseAddress else { return }
                        vDSP_vflt16(src.advanced(by: ch), vDSP_Stride(channelCount), ws, 1, n)
                        var normalize = Float(1.0 / 32768.0)
                        vDSP_vsmul(ws, 1, &normalize, ws, 1, n)
                        applyGainAndMute(ws, count: framesPerChannel)
                        var denormalize = Float(32767.0)
                        vDSP_vsmul(ws, 1, &denormalize, ws, 1, n)
                        vDSP_vfixr16(ws, 1, output.advanced(by: ch), vDSP_Stride(channelCount), n)
                    }
                }
            }
        }
    }

    // MARK: - I24 解码（输出 f32）

    private func decodeI24AsF32(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let output = buffer.assumingMemoryBound(to: Float.self)
        let sampleCount = frames * channelCount
        let srcFrames = min(readBytes / (3 * channelCount), frames)
        let srcSamples = srcFrames * channelCount

        // 初始化输出为 0
        vDSP_vclr(output, 1, vDSP_Length(sampleCount))

        guard srcSamples > 0 else { return }

        ensureI32Workspace(srcSamples)
        ensureFloatWorkspace(srcSamples)

        // 1. 将 24-bit 交错字节解包为 Int32（必须逐字节，但用本地变量加速）
        let frameBytes3 = 3 * channelCount
        var i32Idx = 0
        for frame in 0..<srcFrames {
            let base = frame * frameBytes3
            for ch in 0..<channelCount {
                let idx = base + ch * 3
                let b0 = Int32(bytes[idx])
                let b1 = Int32(bytes[idx + 1])
                let b2 = Int32(bytes[idx + 2])
                var value = (b0 << 8) | (b1 << 16) | (b2 << 24)
                value >>= 8 // 符号扩展
                i32Workspace[i32Idx] = value
                i32Idx += 1
            }
        }

        // 2. vDSP 向量化：Int32 → Float → gain/clamp → 写入交错 f32
        if channelCount == 1 {
            let n = vDSP_Length(srcSamples)
            i32Workspace.withUnsafeBufferPointer { i32Buf in
                    guard let i32Ptr = i32Buf.baseAddress else { return }
                    floatWorkspace.withUnsafeMutableBufferPointer { buf in
                        guard let ws = buf.baseAddress else { return }
                        vDSP_vflt32(i32Ptr, 1, ws, 1, n)
                        var normalize = Float(1.0 / 8_388_608.0)
                        vDSP_vsmul(ws, 1, &normalize, ws, 1, n)
                        applyGainAndMute(ws, count: srcSamples)
                        output.update(from: ws, count: srcSamples)
                }
            }
        } else {
            // 需要按声道 stride 写入交错 f32 输出
            i32Workspace.withUnsafeBufferPointer { i32Buf in
                guard let i32Ptr = i32Buf.baseAddress else { return }
                for ch in 0..<channelCount {
                    let n = vDSP_Length(srcFrames)
                    floatWorkspace.withUnsafeMutableBufferPointer { buf in
                        guard let ws = buf.baseAddress else { return }
                        vDSP_vflt32(i32Ptr.advanced(by: ch), vDSP_Stride(channelCount), ws, 1, n)
                        var normalize = Float(1.0 / 8_388_608.0)
                        vDSP_vsmul(ws, 1, &normalize, ws, 1, n)
                        applyGainAndMute(ws, count: srcFrames)
                        // 写入交错 f32 输出
                        var dstIdx = ch
                        for frame in 0..<srcFrames {
                            output[dstIdx] = ws[frame]
                            dstIdx += channelCount
                        }
                    }
                }
            }
        }
    }

    // MARK: - I32 解码

    private func decodeI32(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let output = buffer.assumingMemoryBound(to: Int32.self)
        let sampleCount = frames * channelCount
        ensureFloatWorkspace(sampleCount)
        let srcSamples = min(readBytes / (4 * channelCount), frames) * channelCount

        guard srcSamples > 0 else {
            output.initialize(repeating: 0, count: sampleCount)
            return
        }

        if channelCount == 1 {
            bytes.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: Int32.self).baseAddress else { return }
                let n = vDSP_Length(srcSamples)

                floatWorkspace.withUnsafeMutableBufferPointer { buf in
                    guard let ws = buf.baseAddress else { return }
                    vDSP_vflt32(src, 1, ws, 1, n)
                    var normalize = Float(1.0 / 2_147_483_648.0)
                    vDSP_vsmul(ws, 1, &normalize, ws, 1, n)
                    applyGainAndMute(ws, count: srcSamples)
                    var denormalize = Float(2_147_483_647.0)
                    vDSP_vsmul(ws, 1, &denormalize, ws, 1, n)
                    vDSP_vfixr32(ws, 1, output, 1, n)
                }
            }
        } else {
            let framesPerChannel = srcSamples / channelCount
            output.initialize(repeating: 0, count: sampleCount)

            bytes.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: Int32.self).baseAddress else { return }
                for ch in 0..<channelCount {
                    let n = vDSP_Length(framesPerChannel)
                    floatWorkspace.withUnsafeMutableBufferPointer { buf in
                        guard let ws = buf.baseAddress else { return }
                        vDSP_vflt32(src.advanced(by: ch), vDSP_Stride(channelCount), ws, 1, n)
                        var normalize = Float(1.0 / 2_147_483_648.0)
                        vDSP_vsmul(ws, 1, &normalize, ws, 1, n)
                        applyGainAndMute(ws, count: framesPerChannel)
                        var denormalize = Float(2_147_483_647.0)
                        vDSP_vsmul(ws, 1, &denormalize, ws, 1, n)
                        vDSP_vfixr32(ws, 1, output.advanced(by: ch), vDSP_Stride(channelCount), n)
                    }
                }
            }
        }
    }

    // MARK: - F32 解码（直通）

    private func decodeF32(buffer: UnsafeMutableRawPointer, bytes: [UInt8], readBytes: Int, frames: Int) {
        let output = buffer.assumingMemoryBound(to: Float.self)
        let sampleCount = frames * channelCount

        // 先零填充
        vDSP_vclr(output, 1, vDSP_Length(sampleCount))

        let srcSamples = min(readBytes / (4 * channelCount), frames) * channelCount
        guard srcSamples > 0 else { return }

        bytes.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Float.self).baseAddress else { return }

            if isMuted {
                // 静音时无需拷贝，已经零填充
                return
            }

            // f32: 增益和钳位与声道无关，整个交错缓冲区可一次性处理。
            output.update(from: src, count: srcSamples)
            var g = gain
            var low: Float = -1.0, high: Float = 1.0
            let n = vDSP_Length(srcSamples)
            vDSP_vsmul(output, 1, &g, output, 1, n)
            vDSP_vclip(output, 1, &low, &high, output, 1, n)
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
