import Foundation
import AVFoundation
import Accelerate

/// 与 Android AudioFormat 编码对应的格式。
/// 数值来自 Android android.media.AudioFormat：
///   ENCODING_PCM_8BIT  = 3   (u8)
///   ENCODING_PCM_16BIT = 2   (i16)
///   ENCODING_PCM_24BIT_PACKED = 21 (i24)
///   ENCODING_PCM_32BIT = 22   (i32)
///   ENCODING_PCM_FLOAT = 4   (f32)
enum AudioSampleFormat: UInt32, CaseIterable {
    case u8 = 3
    case i16 = 2
    case i24 = 21
    case i32 = 22
    case f32 = 4

    var sampleSize: Int {
        switch self {
        case .u8: return 1
        case .i16: return 2
        case .i24: return 3
        case .i32: return 4
        case .f32: return 4
        }
    }

    static func from(string: String) -> AudioSampleFormat? {
        switch string.lowercased() {
        case "u8": return .u8
        case "i16": return .i16
        case "i24": return .i24
        case "i32": return .i32
        case "f32": return .f32
        default: return nil
        }
    }

    /// 将交错字节流转换为单声道 Float 样本（返回新数组）。
    /// 优先使用 ``interleavedBytesToMonoFloat(_:channelCount:into:)`` 以复用缓冲区。
    func interleavedBytesToMonoFloat(_ data: Data, channelCount: Int) -> [Float] {
        guard channelCount > 0, data.count >= sampleSize * channelCount else { return [] }
        let totalFrames = data.count / (sampleSize * channelCount)
        var mono = Array(repeating: Float(0), count: totalFrames)
        interleavedBytesToMonoFloat(data, channelCount: channelCount, into: &mono)
        return mono
    }

    /// 将交错字节流转换为单声道 Float 样本，写入预分配的 buffer。
    /// 调用方负责确保 mono 的 count == totalFrames。
    func interleavedBytesToMonoFloat(_ data: Data, channelCount: Int, into mono: inout [Float]) {
        guard channelCount > 0, data.count >= sampleSize * channelCount else { return }
        let totalFrames = data.count / (sampleSize * channelCount)
        guard totalFrames > 0 else { return }

        // 确保 mono 足够大
        if mono.count < totalFrames {
            mono = Array(repeating: 0, count: totalFrames)
        }

        let n = vDSP_Length(totalFrames)
        var invChan = Float(1.0 / Float(channelCount))

        mono.withUnsafeMutableBufferPointer { monoBuf in
            guard let dst = monoBuf.baseAddress else { return }

            switch self {
            case .u8:
                data.withUnsafeBytes { raw in
                    guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                    // u8 → float [0, 255] → [-1, 1]
                    var scale: Float = 1.0 / 128.0
                    var offset: Float = -1.0
                    if channelCount == 1 {
                        vDSP_vfltu8(src, 1, dst, 1, n)
                        vDSP_vsmsa(dst, 1, &scale, &offset, dst, 1, n)
                    } else {
                        // 逐声道累加到 dst
                        vDSP_vclr(dst, 1, n)
                        let temp = UnsafeMutablePointer<Float>.allocate(capacity: totalFrames)
                        defer { temp.deallocate() }
                        for ch in 0..<channelCount {
                            vDSP_vfltu8(src.advanced(by: ch), vDSP_Stride(channelCount), temp, 1, n)
                            vDSP_vsmsa(temp, 1, &scale, &offset, temp, 1, n)
                            vDSP_vadd(dst, 1, temp, 1, dst, 1, n)
                        }
                        vDSP_vsmul(dst, 1, &invChan, dst, 1, n)
                    }
                }
            case .i16:
                data.withUnsafeBytes { raw in
                    guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
                    if channelCount == 1 {
                        vDSP_vflt16(src, 1, dst, 1, n)
                    } else {
                        vDSP_vclr(dst, 1, n)
                        let temp = UnsafeMutablePointer<Float>.allocate(capacity: totalFrames)
                        defer { temp.deallocate() }
                        for ch in 0..<channelCount {
                            vDSP_vflt16(src.advanced(by: ch), vDSP_Stride(channelCount), temp, 1, n)
                            vDSP_vadd(dst, 1, temp, 1, dst, 1, n)
                        }
                        vDSP_vsmul(dst, 1, &invChan, dst, 1, n)
                    }
                }
            case .i24:
                // 24-bit 需逐字节解包，但使用本地变量减少开销。
                for frame in 0..<totalFrames {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        let offset = (frame * channelCount + ch) * sampleSize
                        sum += decodeI24(data, offset: offset) / Float(1 << 23)
                    }
                    dst[frame] = sum * invChan
                }
            case .i32:
                data.withUnsafeBytes { raw in
                    guard let src = raw.bindMemory(to: Int32.self).baseAddress else { return }
                    if channelCount == 1 {
                        vDSP_vflt32(src, 1, dst, 1, n)
                    } else {
                        vDSP_vclr(dst, 1, n)
                        let temp = UnsafeMutablePointer<Float>.allocate(capacity: totalFrames)
                        defer { temp.deallocate() }
                        for ch in 0..<channelCount {
                            vDSP_vflt32(src.advanced(by: ch), vDSP_Stride(channelCount), temp, 1, n)
                            vDSP_vadd(dst, 1, temp, 1, dst, 1, n)
                        }
                        vDSP_vsmul(dst, 1, &invChan, dst, 1, n)
                    }
                }
            case .f32:
                data.withUnsafeBytes { raw in
                    guard let src = raw.bindMemory(to: Float.self).baseAddress else { return }
                    if channelCount == 1 {
                        memcpy(dst, src, totalFrames * MemoryLayout<Float>.size)
                    } else {
                        vDSP_vclr(dst, 1, n)
                        for ch in 0..<channelCount {
                            // 按 stride 提取单声道并累加
                            let srcCh = src.advanced(by: ch)
                            for i in 0..<totalFrames {
                                dst[i] += srcCh[i * channelCount]
                            }
                        }
                        vDSP_vsmul(dst, 1, &invChan, dst, 1, n)
                    }
                }
            }
        }
    }

    /// 将交错字节流转换为 [-1, 1] 的 Float 平面数组。
    /// 返回 [channel][frame] 的样本。
    func interleavedBytesToPlanarFloat(_ data: Data, channelCount: Int) -> [[Float]] {
        guard channelCount > 0, data.count >= sampleSize * channelCount else { return [] }
        let totalFrames = data.count / (sampleSize * channelCount)
        var channels: [[Float]] = Array(repeating: Array(repeating: 0.0, count: totalFrames), count: channelCount)
        let n = vDSP_Length(totalFrames)

        switch self {
        case .u8:
            data.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                var scale: Float = 1.0 / 128.0
                var offset: Float = -1.0
                for ch in 0..<channelCount {
                    channels[ch].withUnsafeMutableBufferPointer { buf in
                        guard let ptr = buf.baseAddress else { return }
                        vDSP_vfltu8(src.advanced(by: ch), vDSP_Stride(channelCount), ptr, 1, n)
                        vDSP_vsmsa(ptr, 1, &scale, &offset, ptr, 1, n)
                    }
                }
            }
        case .i16:
            data.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
                for ch in 0..<channelCount {
                    channels[ch].withUnsafeMutableBufferPointer { buf in
                        guard let ptr = buf.baseAddress else { return }
                        vDSP_vflt16(src.advanced(by: ch), vDSP_Stride(channelCount), ptr, 1, n)
                    }
                }
            }
        case .i24:
            for frame in 0..<totalFrames {
                for ch in 0..<channelCount {
                    let offset = (frame * channelCount + ch) * sampleSize
                    channels[ch][frame] = decodeI24(data, offset: offset) / Float(1 << 23)
                }
            }
        case .i32:
            data.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: Int32.self).baseAddress else { return }
                for ch in 0..<channelCount {
                    channels[ch].withUnsafeMutableBufferPointer { buf in
                        guard let ptr = buf.baseAddress else { return }
                        vDSP_vflt32(src.advanced(by: ch), vDSP_Stride(channelCount), ptr, 1, n)
                    }
                }
            }
        case .f32:
            data.withUnsafeBytes { raw in
                guard let src = raw.bindMemory(to: Float.self).baseAddress else { return }
                for ch in 0..<channelCount {
                    let srcCh = src.advanced(by: ch)
                    for frame in 0..<totalFrames {
                        channels[ch][frame] = srcCh[frame * channelCount]
                    }
                }
            }
        }

        return channels
    }

    private func decodeI24(_ data: Data, offset: Int) -> Float {
        let b0 = Int32(data[offset])
        let b1 = Int32(data[offset + 1])
        let b2 = Int32(data[offset + 2])
        var value = (b0 << 8) | (b1 << 16) | (b2 << 24)
        value >>= 8  // 符号扩展
        return Float(value)
    }
}

/// 将多通道平面样本转换为单声道（各通道平均）。
func mixToMono(_ planar: [[Float]]) -> [Float] {
    guard planar.count > 0 else { return [] }
    let frameCount = planar[0].count
    var mono = Array(repeating: Float(0), count: frameCount)

    guard frameCount > 0 else { return mono }

    let n = vDSP_Length(frameCount)
    var invCount = Float(1.0 / Float(planar.count))

    mono.withUnsafeMutableBufferPointer { monoBuf in
        guard let dst = monoBuf.baseAddress else { return }
        vDSP_vclr(dst, 1, n)
        for ch in 0..<planar.count {
            planar[ch].withUnsafeBufferPointer { buf in
                guard let ptr = buf.baseAddress else { return }
                vDSP_vadd(dst, 1, ptr, 1, dst, 1, n)
            }
        }
        vDSP_vsmul(dst, 1, &invCount, dst, 1, n)
    }

    return mono
}
