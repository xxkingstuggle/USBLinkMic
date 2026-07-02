import Foundation
import AVFoundation

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

    /// 将交错字节流直接转换为单声道 Float 样本，避免创建中间二维数组。
    func interleavedBytesToMonoFloat(_ data: Data, channelCount: Int) -> [Float] {
        guard channelCount > 0, data.count >= sampleSize * channelCount else { return [] }
        let totalFrames = data.count / (sampleSize * channelCount)
        var mono = Array(repeating: Float(0), count: totalFrames)

        switch self {
        case .u8:
            for frame in 0..<totalFrames {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    let byte = data[(frame * channelCount + ch) * sampleSize]
                    sum += Float(Int16(byte) - 128) / 128.0
                }
                mono[frame] = sum / Float(channelCount)
            }
        case .i16:
            data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Int16.self)
                for frame in 0..<totalFrames {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += Float(ptr[frame * channelCount + ch]) / Float(Int16.max)
                    }
                    mono[frame] = sum / Float(channelCount)
                }
            }
        case .i24:
            for frame in 0..<totalFrames {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    let offset = (frame * channelCount + ch) * sampleSize
                    sum += decodeI24(data, offset: offset) / Float(1 << 23)
                }
                mono[frame] = sum / Float(channelCount)
            }
        case .i32:
            data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Int32.self)
                for frame in 0..<totalFrames {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += Float(ptr[frame * channelCount + ch]) / Float(Int32.max)
                    }
                    mono[frame] = sum / Float(channelCount)
                }
            }
        case .f32:
            data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Float.self)
                for frame in 0..<totalFrames {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += ptr[frame * channelCount + ch]
                    }
                    mono[frame] = sum / Float(channelCount)
                }
            }
        }

        return mono
    }

    /// 将交错字节流转换为 [-1, 1] 的 Float 平面数组。
    /// 返回 [channel][frame] 的样本。
    func interleavedBytesToPlanarFloat(_ data: Data, channelCount: Int) -> [[Float]] {
        guard channelCount > 0, data.count >= sampleSize * channelCount else { return [] }
        let totalFrames = data.count / (sampleSize * channelCount)
        var channels: [[Float]] = Array(repeating: Array(repeating: 0.0, count: totalFrames), count: channelCount)

        switch self {
        case .u8:
            for frame in 0..<totalFrames {
                for ch in 0..<channelCount {
                    let byte = data[(frame * channelCount + ch) * sampleSize]
                    // Android 8-bit PCM 是无符号，归一化到 [-1, 1]
                    let sample = Float(Int16(byte) - 128) / 128.0
                    channels[ch][frame] = sample
                }
            }
        case .i16:
            data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Int16.self)
                for frame in 0..<totalFrames {
                    for ch in 0..<channelCount {
                        let sample = Float(ptr[frame * channelCount + ch]) / Float(Int16.max)
                        channels[ch][frame] = sample
                    }
                }
            }
        case .i24:
            for frame in 0..<totalFrames {
                for ch in 0..<channelCount {
                    let offset = (frame * channelCount + ch) * sampleSize
                    let sample = decodeI24(data, offset: offset) / Float(1 << 23)
                    channels[ch][frame] = sample
                }
            }
        case .i32:
            data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Int32.self)
                for frame in 0..<totalFrames {
                    for ch in 0..<channelCount {
                        let sample = Float(ptr[frame * channelCount + ch]) / Float(Int32.max)
                        channels[ch][frame] = sample
                    }
                }
            }
        case .f32:
            data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Float.self)
                for frame in 0..<totalFrames {
                    for ch in 0..<channelCount {
                        channels[ch][frame] = ptr[frame * channelCount + ch]
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
    for frame in 0..<frameCount {
        var sum: Float = 0
        for ch in 0..<planar.count {
            sum += planar[ch][frame]
        }
        mono[frame] = sum / Float(planar.count)
    }
    return mono
}
