package io.github.teamclouday.androidMic.domain.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import android.util.Log
import android.media.MediaRecorder
import androidx.core.app.NotificationCompat
import io.github.teamclouday.androidMic.AudioFormat
import io.github.teamclouday.androidMic.ChannelCount
import io.github.teamclouday.androidMic.SampleRates
import io.github.teamclouday.androidMic.Mode
import io.github.teamclouday.androidMic.R
import io.github.teamclouday.androidMic.domain.audio.MicAudioManager
import io.github.teamclouday.androidMic.domain.streaming.MicStreamManager
import io.github.teamclouday.androidMic.domain.streaming.DEFAULT_PORT
import io.github.teamclouday.androidMic.network.LinkNetActivity
import io.github.teamclouday.androidMic.network.LinkNetService
import io.github.teamclouday.androidMic.utils.ignore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch


data class ServiceStates(
    var isStreamStarted: Boolean = false,
    var isAudioStarted: Boolean = false,
    var isMuted: Boolean = false,
    var isNetworkStarted: Boolean = false,
    var mode: Mode = Mode.WIFI,
    var controlledByMac: Boolean = false,
    var macConfig: CommandData? = null
)

private const val TAG = "ForegroundService"
const val WAIT_PERIOD = 500L

const val BIND_SERVICE_ACTION = "BIND_SERVICE_ACTION"
const val STOP_STREAM_ACTION = "STOP_STREAM_ACTION"
const val START_MIC_ACTION = "com.zjx.usblinkmic.START_MIC"
const val STOP_MIC_ACTION = "com.zjx.usblinkmic.STOP_MIC"
const val START_ALL_ACTION = "com.zjx.usblinkmic.START_ALL"
const val STOP_ALL_ACTION = "com.zjx.usblinkmic.STOP_ALL"

class ForegroundService : Service() {
    private val scope = CoroutineScope(Dispatchers.Default)

    private inner class ServiceHandler(looper: Looper) : Handler(looper) {
        override fun handleMessage(msg: Message) {
            val commandData = CommandData.fromMessage(msg)
            when (Command.entries[msg.what]) {
                Command.StartStream -> startStream(commandData, msg.replyTo)
                Command.StopStream -> stopStream(msg.replyTo)
                Command.GetStatus -> getStatus(msg.replyTo)
                Command.BindCheck -> {
                    uiMessenger = msg.replyTo
                    replyUi(makeStatusResponse(isConnected = states.isStreamStarted), msg.replyTo)
                }
                Command.Mute -> {
                    states.isMuted = true
                    managerAudio?.mute()
                }
                Command.Unmute -> {
                    states.isMuted = false
                    managerAudio?.unmute()
                }
            }
        }
    }

    private fun reply(replyTo: Messenger?, resp: ResponseData) {
        try {
            replyTo?.send(resp.toResponseMsg())
        } catch (e: Exception) {
            Log.w(TAG, "reply failed", e)
        }
    }

    private fun replyUi(resp: ResponseData, replyTo: Messenger? = null) {
        reply(replyTo, resp)
        reply(uiMessenger, resp)
    }

    private lateinit var handlerThread: HandlerThread
    private lateinit var serviceLooper: Looper
    private lateinit var serviceHandler: ServiceHandler
    private lateinit var serviceMessenger: Messenger

    private var managerAudio: MicAudioManager? = null
    private var managerStream: MicStreamManager? = null

    private val states = ServiceStates()

    private var isBind = false
    private var uiMessenger: Messenger? = null

    override fun onCreate() {
        Log.d(TAG, "onCreate")
        handlerThread = HandlerThread("MicServiceStart", Process.THREAD_PRIORITY_BACKGROUND)
        handlerThread.start()
        serviceLooper = handlerThread.looper
        serviceHandler = ServiceHandler(handlerThread.looper)
        serviceMessenger = Messenger(serviceHandler)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = getString(R.string.app_name)
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance)
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        Log.d(TAG, "onBind")
        isBind = true
        return serviceMessenger.binder
    }

    private var serviceShouldStop = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")
        when (intent?.action) {
            STOP_STREAM_ACTION -> {
                serviceHandler.post { stopStream(null); stopSelf(startId) }
            }
            START_MIC_ACTION -> {
                startMicForeground()
                serviceHandler.post {
                    val cmd = defaultAdbCommand(intent)
                    states.controlledByMac = true
                    states.macConfig = cmd
                    startStream(cmd, null)
                }
            }
            STOP_MIC_ACTION -> {
                serviceHandler.post {
                    states.controlledByMac = false
                    states.macConfig = null
                    stopStream(null); stopSelf(startId)
                }
            }
            START_ALL_ACTION -> {
                startMicForeground()
                serviceHandler.post {
                    val cmd = defaultAdbCommand(intent)
                    states.controlledByMac = true
                    states.macConfig = cmd
                    startStream(cmd, null)
                }
                startNetworkShare(intent)
            }
            STOP_ALL_ACTION -> {
                serviceHandler.post {
                    stopStream(null)
                    stopNetworkShare()
                    stopSelf(startId)
                }
            }
            BIND_SERVICE_ACTION -> {
                isBind = true; serviceShouldStop = false
            }
            else -> {
                Log.w(TAG, "unknown action: ${intent?.action}")
            }
        }
        return START_NOT_STICKY
    }

    private fun defaultAdbCommand(intent: Intent?): CommandData {
        val port = intent?.getIntExtra("port", DEFAULT_PORT) ?: DEFAULT_PORT
        val sampleRate = intent?.getIntExtra("sampleRate", SampleRates.S44100.value)
            ?.let { value -> SampleRates.entries.firstOrNull { it.value == value } }
            ?: SampleRates.S44100
        val channelCount = intent?.getIntExtra("channelCount", ChannelCount.Mono.value)
            ?.let { value -> ChannelCount.entries.firstOrNull { it.value == value } }
            ?: ChannelCount.Mono
        val audioFormatName = intent?.getStringExtra("audioFormat")
        val audioFormat = AudioFormat.entries.firstOrNull {
            it.name.equals(audioFormatName, ignoreCase = true) ||
                    it.description.equals(audioFormatName, ignoreCase = true)
        } ?: AudioFormat.I16
        val audioSourceName = intent?.getStringExtra("audioSource")
        val audioSource = io.github.teamclouday.androidMic.AudioSource.entries.firstOrNull {
            it.name.equals(audioSourceName, ignoreCase = true)
        }?.getSource() ?: MediaRecorder.AudioSource.MIC

        return CommandData(
            command = Command.StartStream,
            mode = Mode.ADB,
            port = port,
            sampleRate = sampleRate,
            channelCount = channelCount,
            audioFormat = audioFormat,
            audioSource = audioSource,
        )
    }

    private fun startNetworkShare(intent: Intent?) {
        val dnsServers = intent?.getStringArrayExtra("dnsServers") ?: arrayOf("8.8.8.8")
        val routes = intent?.getStringArrayExtra("routes") ?: arrayOf("0.0.0.0/0")
        val startIntent = Intent(applicationContext, LinkNetActivity::class.java).apply {
            action = LinkNetActivity.ACTION_LINK_NET_START
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(LinkNetActivity.EXTRA_DNS_SERVERS, dnsServers)
            putExtra(LinkNetActivity.EXTRA_ROUTES, routes)
        }
        startActivity(startIntent)
        states.isNetworkStarted = true
    }

    private fun stopNetworkShare() {
        LinkNetService.stop(applicationContext)
        states.isNetworkStarted = false
    }

    override fun onUnbind(intent: Intent?): Boolean {
        super.onUnbind(intent)
        Log.d(TAG, "onUnbind")
        isBind = false
        uiMessenger = null
        if (!states.isStreamStarted) {
            serviceShouldStop = true
            scope.launch {
                delay(3000L)
                if (serviceShouldStop) stopService()
            }
        }
        return true
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy")
        stopService()
    }

    private fun stopService() {
        Log.d(TAG, "stopService")
        managerAudio?.shutdown()
        managerAudio = null
        managerStream?.shutdown()
        managerStream = null
        if (this::serviceLooper.isInitialized) {
            serviceLooper.quitSafely()
        }
        if (this::handlerThread.isInitialized && Thread.currentThread() != handlerThread) {
            ignore { handlerThread.join(WAIT_PERIOD) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        stopSelf()
    }

    private fun startMicForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(3, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(3, notification)
        }
    }

    private fun buildNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(getString(R.string.app_name))
        .setContentText(getString(R.string.notification_info))
        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        .setOngoing(true)
        .build()

    private fun startStream(msg: CommandData, replyTo: Messenger?) {
        states.isMuted = false
        if (states.isStreamStarted) {
            replyUi(makeStatusResponse(msg = getString(R.string.stream_already_started)), replyTo)
            return
        }
        shutdownStream()
        shutdownAudio()

        Log.d(TAG, "startStream [start] mode=${msg.mode} port=${msg.port}")

        try {
            managerStream = MicStreamManager(applicationContext, scope, msg.mode!!, msg.ip, msg.port)
        } catch (e: IllegalArgumentException) {
            Log.d(TAG, "startStream failed: ${e.message}")
            replyUi(makeStatusResponse(msg = getString(R.string.error) + e.message, isConnected = false), replyTo)
            return
        }

        if (managerStream?.connect() != true || managerStream?.isConnected() != true) {
            Log.d(TAG, "startStream failed: could not connect")
            replyUi(makeStatusResponse(msg = getString(R.string.failed_to_connect), isConnected = false), replyTo)
            shutdownStream()
            if (!isBind) { stopService() }
            return
        }

        if (!startAudio(msg, replyTo)) {
            shutdownStream(); shutdownAudio()
            if (!isBind) { stopService() }
            return
        }

        managerStream?.start(
            managerAudio!!.audioStream { levels ->
                if (levels.isNotEmpty()) {
                    replyUi(ResponseData(waveLevels = levels), replyTo)
                }
            },
            serviceMessenger
        )
        states.isStreamStarted = true
        states.mode = msg.mode!!
        Log.d(TAG, "startStream [connected] ${managerStream?.getInfo()}")
        replyUi(makeStatusResponse(msg = getString(R.string.connected_device) + (managerStream?.getInfo() ?: ""), isConnected = true), replyTo)
    }

    private fun makeStatusResponse(
        msg: String? = null,
        isConnected: Boolean? = null,
    ): ResponseData {
        return ResponseData(
            msg = msg,
            isConnected = isConnected,
            isMuted = states.isMuted,
            controlledByMac = states.controlledByMac,
            activeMode = states.macConfig?.mode ?: states.mode,
            activeSampleRate = states.macConfig?.sampleRate,
            activeChannelCount = states.macConfig?.channelCount,
            activeAudioFormat = states.macConfig?.audioFormat,
        )
    }

    fun stopStream(replyTo: Messenger?) {
        Log.d(TAG, "stopStream")
        stopAudio(replyTo)
        shutdownStream()
        states.controlledByMac = false
        states.macConfig = null
        replyUi(ResponseData(msg = getString(R.string.device_disconnected), isConnected = false, isMuted = states.isMuted, waveLevels = FloatArray(0)), replyTo)
        if (!isBind) { stopService() }
    }

    private fun shutdownStream() {
        val m = managerStream
        managerStream = null
        states.isStreamStarted = false
        m?.shutdown()
    }

    private fun startAudio(msg: CommandData, replyTo: Messenger?): Boolean {
        if (states.isAudioStarted) {
            replyUi(makeStatusResponse(msg = getString(R.string.microphone_already_started)), replyTo)
            return true
        }
        Log.d(TAG, "startAudio [start]")
        managerAudio?.shutdown()
        try {
            managerAudio = MicAudioManager(applicationContext, scope, msg.sampleRate!!.value, msg.audioFormat!!.value, msg.channelCount!!.value, msg.audioSource!!)
        } catch (e: IllegalArgumentException) {
            replyUi(makeStatusResponse(msg = getString(R.string.error) + e.message, isConnected = false), replyTo)
            return false
        }
        managerAudio?.start()
        Log.d(TAG, "startAudio [recording]")
        states.isAudioStarted = true
        replyUi(makeStatusResponse(msg = getString(R.string.mic_start_recording)), replyTo)
        return true
    }

    private fun stopAudio(replyTo: Messenger?) {
        Log.d(TAG, "stopAudio")
        shutdownAudio()
        replyUi(makeStatusResponse(msg = getString(R.string.recording_stopped)), replyTo)
    }

    private fun shutdownAudio() {
        val a = managerAudio
        managerAudio = null
        states.isAudioStarted = false
        a?.shutdown()
    }

    private fun getStatus(replyTo: Messenger) {
        reply(replyTo, makeStatusResponse(isConnected = states.isStreamStarted))
    }
}
