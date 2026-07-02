package io.github.teamclouday.androidMic.domain.audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.util.Log
import androidx.core.content.ContextCompat
import io.github.teamclouday.androidMic.domain.service.AudioPacket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.nio.ByteOrder


private const val TAG: String = "MicAM"

// manage microphone recording
class MicAudioManager(
    ctx: Context,
    val scope: CoroutineScope,
    val sampleRate: Int,
    val audioFormat: Int,
    val channelCount: Int,
    val audioSource: Int,
) {

    companion object {
        const val RECORD_DELAY_MS = 100L
    }

    private val recorder: AudioRecord
    private val bufferSize: Int
    private val readByteSize: Int
    private val readFloatSize: Int
    private val buffer: ByteArray
    private val bufferFloat: FloatArray
    private val bufferFloatConvert: ByteBuffer
    private var streamJob: Job? = null

    private var isMuted = false

    init {
        // check microphone
        require(ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)) {
            "Microphone is not detected on this device"
        }
        require(
            ContextCompat.checkSelfPermission(
                ctx,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            "Microphone recording is not permitted"
        }

        // get minimum buffer size
        val channelConfig =
            if (channelCount == 2) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
        bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            channelConfig,
            audioFormat,
        )

        require(bufferSize != AudioRecord.ERROR && bufferSize != AudioRecord.ERROR_BAD_VALUE) {
            "Microphone buffer size ($bufferSize) is invalid\nAudio format is likely not supported"
        }

        // init recorder
        recorder = AudioRecord(
            audioSource,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize,
        )

        // check if recorder is initialized
        require(recorder.state == AudioRecord.STATE_INITIALIZED) {
            "Microphone recording failed to initialize"
        }

        val bytesPerSample = bytesPerSample(audioFormat)
        val targetFrames = maxOf(1, sampleRate / 50)
        readByteSize = minOf(bufferSize, maxOf(bytesPerSample * channelCount, targetFrames * channelCount * bytesPerSample))
        readFloatSize = minOf(bufferSize / 4, maxOf(channelCount, targetFrames * channelCount))
        buffer = ByteArray(readByteSize)
        bufferFloat = FloatArray(readFloatSize)
        bufferFloatConvert = ByteBuffer.allocate(readFloatSize * 4).order(ByteOrder.nativeOrder())
    }

    // audio stream publisher
    fun audioStream(onWaveLevels: ((FloatArray) -> Unit)? = null): Flow<AudioPacket> = channelFlow {
        // launch in scope so infinite loop will be canceled when scope exits
        streamJob = scope.launch {
            while (true) {

                if (isMuted) {
                    delay(RECORD_DELAY_MS)
                    continue
                }

                if (recorder.state != AudioRecord.STATE_INITIALIZED || recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    delay(RECORD_DELAY_MS)
                    continue
                }

                val readCount: Int // number of samples read (for float) or number of bytes read (for int)
                val packetBuffer: ByteArray

                if (audioFormat == AudioFormat.ENCODING_PCM_FLOAT) {
                    readCount =
                        recorder.read(bufferFloat, 0, bufferFloat.size, AudioRecord.READ_BLOCKING)

                    if (readCount > 0) {
                        bufferFloatConvert.clear()
                        bufferFloatConvert.asFloatBuffer().put(bufferFloat, 0, readCount)
                        packetBuffer = bufferFloatConvert.array().copyOf(readCount * 4)
                    } else {
                        packetBuffer = ByteArray(0)
                    }
                } else {
                    readCount = recorder.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)

                    if (readCount > 0) {
                        packetBuffer = ByteArray(readCount)
                        buffer.copyInto(packetBuffer, 0, 0, readCount)
                    } else {
                        packetBuffer = ByteArray(0)
                    }
                }

                if (readCount <= 0) {
                    delay(RECORD_DELAY_MS)
                    continue
                }

                val waveLevels = buildWaveLevels(packetBuffer, audioFormat, channelCount)
                onWaveLevels?.invoke(waveLevels)
                send(
                    AudioPacket(
                        buffer = packetBuffer,
                        sampleRate = sampleRate,
                        audioFormat = audioFormat,
                        channelCount = channelCount,
                        waveLevels = waveLevels
                    )
                )
            }
        }

        awaitClose {
            streamJob?.cancel()
        }
    }

    fun mute() {
        isMuted = true
    }

    fun unmute() {
        isMuted = false
    }

    // start recording
    fun start() {
        recorder.startRecording()
        Log.d(TAG, "start")
    }

    // stop recording
    fun stop() {
        recorder.stop()
        Log.d(TAG, "stop")
    }

    // shutdown manager
    // should not call any methods after calling
    fun shutdown() {
        recorder.stop()
        recorder.release()
        streamJob?.cancel()
        Log.d(TAG, "shutdown")
    }

    private fun bytesPerSample(format: Int): Int = when (format) {
        AudioFormat.ENCODING_PCM_8BIT -> 1
        AudioFormat.ENCODING_PCM_16BIT -> 2
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
        AudioFormat.ENCODING_PCM_32BIT -> 4
        AudioFormat.ENCODING_PCM_FLOAT -> 4
        else -> 2
    }

    private fun buildWaveLevels(data: ByteArray, format: Int, channels: Int): FloatArray {
        if (data.isEmpty()) return FloatArray(0)
        val sampleBytes = bytesPerSample(format)
        val frameCount = data.size / sampleBytes / maxOf(1, channels)
        if (frameCount <= 0) return FloatArray(0)

        val bucketCount = minOf(12, maxOf(1, frameCount / 64))
        val framesPerBucket = maxOf(1, frameCount / bucketCount)
        val levels = FloatArray(bucketCount)
        for (bucket in 0 until bucketCount) {
            val start = bucket * framesPerBucket
            val end = if (bucket == bucketCount - 1) frameCount else minOf(frameCount, start + framesPerBucket)
            var peak = 0f
            for (frame in start until end) {
                val sample = kotlin.math.abs(readSample(data, format, channels, frame, 0))
                if (sample > peak) peak = sample
            }
            levels[bucket] = peak.coerceIn(0f, 1f)
        }
        return levels
    }

    private fun readSample(data: ByteArray, format: Int, channels: Int, frame: Int, channel: Int): Float {
        val sampleBytes = bytesPerSample(format)
        val offset = (frame * maxOf(1, channels) + channel.coerceAtMost(maxOf(0, channels - 1))) * sampleBytes
        if (offset + sampleBytes > data.size) return 0f
        return when (format) {
            AudioFormat.ENCODING_PCM_8BIT -> ((data[offset].toInt() and 0xff) - 128) / 128f
            AudioFormat.ENCODING_PCM_16BIT -> {
                val value = ((data[offset + 1].toInt() shl 8) or (data[offset].toInt() and 0xff)).toShort()
                value / Short.MAX_VALUE.toFloat()
            }
            AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                var value = (data[offset].toInt() and 0xff) or ((data[offset + 1].toInt() and 0xff) shl 8) or ((data[offset + 2].toInt() and 0xff) shl 16)
                if ((value and 0x800000) != 0) value = value or -0x1000000
                value / 0x7fffff.toFloat()
            }
            AudioFormat.ENCODING_PCM_32BIT -> {
                val value = (data[offset].toInt() and 0xff) or
                        ((data[offset + 1].toInt() and 0xff) shl 8) or
                        ((data[offset + 2].toInt() and 0xff) shl 16) or
                        (data[offset + 3].toInt() shl 24)
                value / Int.MAX_VALUE.toFloat()
            }
            AudioFormat.ENCODING_PCM_FLOAT -> ByteBuffer.wrap(data, offset, 4).order(ByteOrder.nativeOrder()).float
            else -> 0f
        }
    }
}
