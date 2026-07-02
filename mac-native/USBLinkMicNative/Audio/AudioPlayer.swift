import Foundation
import AVFoundation

/// 管理 Mac 端音频输出：把从手机传来的样本写入 ring buffer，再通过 AVAudioEngine 播出。
final class AudioPlayer: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var ringBuffer: SampleRingBuffer?

    private var sampleRate: Double = 44100
    private var channelCount: Int = 1
    private var format: AVAudioFormat?

    var gain: Float = 1.0
    var isMuted: Bool = false

    // 预分配的读取缓冲区，避免 AVAudioEngine 渲染线程实时堆分配。
    private var readBuffer: [Float] = []

    /// 启动播放器。
    func start(sampleRate: Double, channelCount: Int, outputDeviceID: AudioDeviceID?) throws {
        stop()

        self.sampleRate = sampleRate
        self.channelCount = channelCount

        let channels = AVAudioChannelCount(channelCount)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            throw AudioPlayerError.badFormat
        }
        self.format = format

        let engine = AVAudioEngine()

        // 如指定了输出设备，临时把系统默认输出切过去。
        if let deviceID = outputDeviceID {
            setOutputDevice(deviceID: deviceID)
        }

        // ring buffer 容量按 1.5 秒计算（单声道 Float 样本）。
        let capacity = Int(sampleRate * 1.5)
        let ring = SampleRingBuffer(capacity: max(capacity, 8192))
        self.ringBuffer = ring

        let sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            let ch = max(1, Int(self.channelCount))

            // 预分配重用的单声道缓冲区。Ring buffer 始终保存单声道 Float。
            if self.readBuffer.count < frames {
                self.readBuffer = Array(repeating: Float(0), count: frames)
            }
            _ = self.ringBuffer?.read(into: &self.readBuffer, count: frames)

            let gain = self.gain
            let muted = self.isMuted

            // 一次遍历完成增益/静音/削波，避免后续逐样本循环。
            for i in 0..<frames {
                let s = muted ? 0 : self.readBuffer[i] * gain
                self.readBuffer[i] = max(-1.0, min(1.0, s))
            }

            // 将单声道样本复制到所有输出通道（memcpy 级别）。
            self.readBuffer.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                for chIndex in 0..<ch {
                    guard let mData = ablPointer[chIndex].mData else { continue }
                    let ptr = mData.bindMemory(to: Float.self, capacity: frames)
                    ptr.update(from: srcBase, count: frames)
                }
            }

            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        try engine.start()
        self.engine = engine
    }

    func stop() {
        engine?.stop()
        engine = nil
        ringBuffer?.reset()
    }

    /// 写入音频包数据。可在任意线程调用。
    @discardableResult
    func write(packet: AudioPacketMessage) -> [Float] {
        guard let format = AudioSampleFormat(rawValue: packet.audioFormat) else { return [] }
        let mono = format.interleavedBytesToMonoFloat(packet.buffer, channelCount: Int(packet.channelCount))

        // 更新内部采样率/声道（如果后续包变化）。
        sampleRate = Double(packet.sampleRate)
        channelCount = max(1, Int(packet.channelCount))

        ringBuffer?.write(mono)
        return mono
    }

    private func setOutputDevice(deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }
}

enum AudioPlayerError: Error {
    case badFormat
    case engineStartFailed
}
