package io.github.teamclouday.androidMic.domain.streaming

import Message.Messages
import android.content.Context
import android.net.ConnectivityManager
import android.os.Messenger
import android.util.Log
import com.google.protobuf.ByteString
import io.github.teamclouday.androidMic.domain.service.AudioPacket
import io.github.teamclouday.androidMic.domain.service.Command
import io.github.teamclouday.androidMic.domain.service.CommandData
import io.github.teamclouday.androidMic.utils.ignore
import io.github.teamclouday.androidMic.utils.toBigEndianU32
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException

class TcpStreamer(
    private val scope: CoroutineScope,
    private val tag: String,
    private val ip: String,
    private var port: Int
) : Streamer {

    @Volatile
    private var socket: Socket? = null
    private var streamJob: Job? = null

    companion object {

        fun wifi(
            ctx: Context,
            scope: CoroutineScope,
            ip: String,
            port: Int
        ): TcpStreamer {

            // check WIFI
            // reference: https://stackoverflow.com/questions/70107145/connectivity-manager-allnetworks-deprecated
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val net = cm.activeNetwork
            require(net != null) {
                "Wifi not available"
            }
            require(cm.getNetworkCapabilities(net) != null) {
                "Wifi not available"
            }

            return TcpStreamer(
                scope = scope,
                tag = "WifiStreamer",
                ip = ip,
                port = port
            )
        }

        fun adb(
            scope: CoroutineScope,
            port: Int
        ) = TcpStreamer(
            scope = scope,
            tag = "AdbStreamer",
            ip = "127.0.0.1",
            port = port
        )
    }

    // connect to server
    override fun connect(): Boolean {

        val p = port
        Log.d(tag, "connect [start] ip=$ip port=$p")
        val socket = createSocket(p, 5000) ?: return false

        if (!handShake(socket)) {
            Log.d(tag, "connect [Socket]: handshake error")
            ignore { socket.close() }
            return false
        }

        this.socket = socket
        Log.d(tag, "connect [success] ip=$ip port=$p")
        return true
    }

    // stream data through socket
    override fun start(audioStream: Flow<AudioPacket>, tx: Messenger) {
        streamJob?.cancel()

        streamJob = scope.launch {
            audioStream.collect { data ->
                val currentSocket = socket ?: return@collect
                if (!currentSocket.isConnected || currentSocket.isClosed) return@collect

                try {
                    val message = Messages.AudioPacketMessage.newBuilder()
                        .setBuffer(ByteString.copyFrom(data.buffer))
                        .setSampleRate(data.sampleRate)
                        .setAudioFormat(data.audioFormat)
                        .setChannelCount(data.channelCount)
                        .build()
                    val pack = message.toByteArray()

                    // Combine length prefix and body into one buffer to halve the syscall count.
                    // Avoid per-packet flush; the OS and TCP will push data promptly on a local ADB reverse pipe.
                    val out = ByteArray(4 + pack.size)
                    val prefix = pack.size.toBigEndianU32()
                    prefix.copyInto(out, 0)
                    pack.copyInto(out, 4)
                    currentSocket.outputStream.write(out)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w(tag, "stream failed; stopping", e)
                    closeIfCurrent(currentSocket)
                    try {
                        tx.send(CommandData(Command.StopStream).toCommandMsg())
                    } catch (sendError: Exception) {
                        Log.w(tag, "failed to notify service about stream failure", sendError)
                    }
                    throw CancellationException("stream stopped after socket failure")
                }
            }
        }
    }

    // disconnect from server
    override fun disconnect(): Boolean {
        val currentSocket = socket
        socket = null
        streamJob?.cancel()
        streamJob = null
        if (currentSocket == null) return false
        try {
            currentSocket.close()
        } catch (e: IOException) {
            Log.d(tag, "disconnect [close]: ${e.message}")
            return false
        }
        Log.d(tag, "disconnect: complete")
        return true
    }

    private fun closeIfCurrent(failedSocket: Socket) {
        if (socket === failedSocket) {
            socket = null
        }
        try {
            failedSocket.close()
        } catch (e: IOException) {
            Log.d(tag, "stream failure close: ${e.message}")
        }
    }

    // shutdown streamer
    override fun shutdown() {
        disconnect()
    }

    // get connected server information
    override fun getInfo(): String {
        val currentSocket = socket ?: return ""
        return "[Device Address]:${currentSocket.remoteSocketAddress}"
    }

    // return true if is connected for streaming
    override fun isAlive(): Boolean {
        val currentSocket = socket ?: return false
        return currentSocket.isConnected && !currentSocket.isClosed
    }


    fun createSocket(p: Int, timeout: Int): Socket? {
        val socket = Socket()
        return try {
            socket.connect(InetSocketAddress(ip, p), timeout)
            socket.soTimeout = 5000
            socket
        } catch (e: IOException) {
            Log.d(tag, "connect [Socket] IOException: ${e.message}")
            null
        } catch (e: SocketTimeoutException) {
            Log.d(tag, "connect [Socket] timeout: ${e.message}")
            null
        }
    }

    fun handShake(
        socket: Socket,
    ): Boolean {

        return try {
            socket.soTimeout = 5000
            val out = socket.getOutputStream()
            out.write(CHECK_1.toByteArray())
            out.flush()

            val input = socket.getInputStream()
            val msgBuf = ByteArray(CHECK_2.length)
            var offset = 0
            while (offset < msgBuf.size) {
                val read = input.read(msgBuf, offset, msgBuf.size - offset)
                if (read < 0) {
                    Log.d(tag, "handshake: server closed before response")
                    return false
                }
                offset += read
            }
            val ok = msgBuf.contentEquals(CHECK_2.toByteArray())
            if (!ok) {
                Log.d(tag, "handshake: unexpected response: ${msgBuf.toString(Charsets.UTF_8)}")
            }
            ok

        } catch (e: Exception) {
            Log.d(tag, "handshake error: ${e.message}")
            false
        }
    }
}
