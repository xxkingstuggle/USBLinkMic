import Foundation

/// 与 Rust / Android 通信的音频包结构。
/// proto 定义在 mac/src/proto/messages.proto 中的 AudioPacketMessage。
struct AudioPacketMessage {
    var buffer: Data = Data()
    var sampleRate: UInt32 = 0
    var channelCount: UInt32 = 0
    var audioFormat: UInt32 = 0
}

enum AudioPacketError: Error {
    case truncated
    case invalidField
    case invalidLength
}

/// 手写解码：只处理 proto3 中 AudioPacketMessage 的 4 个字段。
/// field 1 (buffer)     wire type 2 (length-delimited)
/// field 2 (sampleRate) wire type 0 (varint)
/// field 3 (channelCount) wire type 0
/// field 4 (audioFormat) wire type 0
func decodeAudioPacketMessage(_ data: Data) throws -> AudioPacketMessage {
    var result = AudioPacketMessage()
    var i = 0

    func decodeVarint() throws -> UInt32 {
        var value: UInt32 = 0
        var shift = 0
        while true {
            guard i < data.count else { throw AudioPacketError.truncated }
            let byte = data[i]
            i += 1
            value |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            if shift > 28 { throw AudioPacketError.invalidLength }
        }
        return value
    }

    while i < data.count {
        let tag = try decodeVarint()
        let fieldNumber = Int(tag >> 3)
        let wireType = tag & 0x07

        switch wireType {
        case 0: // varint
            let value = try decodeVarint()
            switch fieldNumber {
            case 2: result.sampleRate = value
            case 3: result.channelCount = value
            case 4: result.audioFormat = value
            default: break
            }
        case 2: // length-delimited
            let length = try decodeVarint()
            guard length <= UInt32(data.count - i) else { throw AudioPacketError.truncated }
            let start = i
            let end = i + Int(length)
            switch fieldNumber {
            case 1: result.buffer = data[start..<end]
            default: break
            }
            i = end
        default:
            throw AudioPacketError.invalidField
        }
    }

    return result
}
