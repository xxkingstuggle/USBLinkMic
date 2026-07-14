package io.github.teamclouday.androidMic.ui

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.github.teamclouday.androidMic.AndroidMicApp
import io.github.teamclouday.androidMic.AudioFormat
import io.github.teamclouday.androidMic.AudioSource
import io.github.teamclouday.androidMic.ChannelCount
import io.github.teamclouday.androidMic.DefaultStates
import io.github.teamclouday.androidMic.Mode
import io.github.teamclouday.androidMic.SampleRates
import io.github.teamclouday.androidMic.network.LinkNetService
import io.github.teamclouday.androidMic.domain.service.*
import io.github.teamclouday.androidMic.utils.Either
import io.github.teamclouday.androidMic.utils.ignore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainViewModel : ViewModel() {
    val prefs get() = AndroidMicApp.appModule.appPreferences()

    var textLog by mutableStateOf("")
    var isStreamStarted by mutableStateOf(false)
    var isNetworkStarted by mutableStateOf(false)
    var isNetworkConnecting by mutableStateOf(false)
    var macToPhoneStatus by mutableStateOf("等待 Mac 端开启")
    var isMuted by mutableStateOf(false)
    var micWaveLevels by mutableStateOf(List(48) { 0f })
    var isPhoneToMacUsbActive by mutableStateOf(false)
    var phoneToMacUsbStatus by mutableStateOf("未检测到")

    // active configuration reported by the service (may differ from prefs when controlled by Mac)
    var controlledByMac by mutableStateOf(false)
    var activeMode by mutableStateOf<Mode?>(null)
    var activeSampleRate by mutableStateOf<SampleRates?>(null)
    var activeChannelCount by mutableStateOf<ChannelCount?>(null)
    var activeAudioFormat by mutableStateOf<AudioFormat?>(null)

    var requestedConnect: (() -> Unit)? = null

    private var service: Messenger? = null
    private var responseMessenger: Messenger? = null

    fun handlerServiceResponse() {
        responseMessenger = Messenger(object : Handler(Looper.getMainLooper()) {
            override fun handleMessage(msg: Message) {
                val response = ResponseData.fromMessage(msg)
                response.msg?.let { addLogMessage(it) }
                response.isConnected?.let {
                    isStreamStarted = it
                    if (!it) micWaveLevels = List(48) { 0f }
                }
                response.isMuted?.let { isMuted = it }
                response.waveLevels?.let { appendWaveLevels(it.toList()) }
                response.controlledByMac?.let { controlledByMac = it }
                response.activeMode?.let { activeMode = it }
                response.activeSampleRate?.let { activeSampleRate = it }
                response.activeChannelCount?.let { activeChannelCount = it }
                response.activeAudioFormat?.let { activeAudioFormat = it }
            }
        })
        service = AndroidMicApp.service
    }

    fun bindCheck() {
        service = AndroidMicApp.service
        sendCommand(Command.BindCheck.ordinal)
    }

    fun connect(beforeConnect: () -> Unit) {
        beforeConnect()
        viewModelScope.launch {
            val data = withContext(Dispatchers.IO) {
                CommandData.fromPref(prefs, Command.StartStream)
            }
            if (data is Either.Left) {
                val currentService = service ?: AndroidMicApp.service
                if (currentService == null) {
                    addLogMessage("麦克风服务还未连接，请稍等一秒再试")
                    isStreamStarted = false
                    return@launch
                }
                service = currentService
                addLogMessage("手机麦克风：正在连接 Mac 端口 ${data.value.port ?: "默认"}")
                sendCommand(data.value.toCommandMsg())
            } else {
                addLogMessage("请先完成网络设置（IP/端口）")
            }
        }
    }

    fun disconnect() {
        sendCommand(Command.StopStream.ordinal)
        micWaveLevels = List(48) { 0f }
    }

    fun mute() { sendCommand(Command.Mute.ordinal) }
    fun unmute() { sendCommand(Command.Unmute.ordinal) }

    private data class UsbStatus(val active: Boolean, val description: String)
    private var usbStatusJob: Job? = null

    fun refreshPhoneToMacUsbStatus() {
        usbStatusJob?.cancel()
        usbStatusJob = viewModelScope.launch {
            val status = withContext(Dispatchers.IO) {
                try {
                    val interfaces = java.net.NetworkInterface.getNetworkInterfaces().toList()
                        .filter { iface ->
                            val name = iface.name.lowercase()
                            iface.isUp && (name.contains("ncm") || name.contains("rndis") || name.contains("usb"))
                        }
                    val usbFunction = try {
                        val process = ProcessBuilder("getprop", "sys.usb.config")
                            .redirectErrorStream(true)
                            .start()
                        try {
                            process.inputStream.bufferedReader().use { it.readText().trim() }
                        } finally {
                            process.destroy()
                        }
                    } catch (_: Exception) {
                        ""
                    }
                    val active = usbFunction.contains("ncm", true) ||
                            usbFunction.contains("rndis", true) ||
                            interfaces.isNotEmpty()
                    val description = when {
                        active && interfaces.isNotEmpty() -> {
                            val info = interfaces.joinToString { iface ->
                                val ip = iface.inetAddresses.toList()
                                    .filterIsInstance<java.net.Inet4Address>()
                                    .firstOrNull()?.hostAddress ?: "—"
                                "${iface.name} $ip"
                            }
                            "已开启：$info"
                        }
                        active -> "已开启：$usbFunction"
                        else -> usbFunction.ifBlank { "未检测到 USB 有线供网" }
                    }
                    UsbStatus(active, description)
                } catch (_: Exception) {
                    UsbStatus(false, "未检测到 USB 有线供网")
                }
            }
            isPhoneToMacUsbActive = status.active
            phoneToMacUsbStatus = status.description
        }
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var macToPhoneStatusJob: Job? = null

    private fun refreshMacToPhoneStatus() {
        when (LinkNetService.getConnectionState()) {
            LinkNetService.STATE_CONNECTED -> {
                isNetworkStarted = true
                isNetworkConnecting = false
                macToPhoneStatus = "已通过 Mac relay 连接"
            }
            LinkNetService.STATE_CONNECTING -> {
                isNetworkStarted = false
                isNetworkConnecting = true
                macToPhoneStatus = "正在等待 Mac relay…"
            }
            else -> {
                isNetworkStarted = false
                isNetworkConnecting = false
                macToPhoneStatus = "等待 Mac 端开启"
            }
        }
    }

    fun startNetworkMonitoring() {
        val cm = AndroidMicApp.context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = refreshPhoneToMacUsbStatus()
            override fun onLost(network: Network) = refreshPhoneToMacUsbStatus()
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = refreshPhoneToMacUsbStatus()
            override fun onLinkPropertiesChanged(network: Network, props: LinkProperties) = refreshPhoneToMacUsbStatus()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            cm.registerDefaultNetworkCallback(callback)
        } else {
            cm.registerNetworkCallback(NetworkRequest.Builder().build(), callback)
        }
        networkCallback = callback
        refreshPhoneToMacUsbStatus()
        macToPhoneStatusJob?.cancel()
        macToPhoneStatusJob = viewModelScope.launch {
            while (isActive) {
                refreshMacToPhoneStatus()
                delay(500)
            }
        }
    }

    fun stopNetworkMonitoring() {
        networkCallback?.let { ignore { (AndroidMicApp.context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it) } }
        networkCallback = null
        macToPhoneStatusJob?.cancel()
        macToPhoneStatusJob = null
    }

    fun cleanLog() { textLog = "" }

    fun updateMode(value: Mode) = viewModelScope.launch {
        val currentMode = activeMode ?: prefs.mode.get()
        if (isStreamStarted && value != currentMode) {
            disconnect()
        }
        prefs.mode.update(value)
    }
    fun updateIp(value: String) = viewModelScope.launch { prefs.ip.update(value.trim()) }
    fun updatePort(value: String) = viewModelScope.launch {
        val sanitized = value.filter { it.isDigit() }.take(5)
        val port = sanitized.toIntOrNull()
        val validValue = if (sanitized.isEmpty() || (port != null && port in 1..65535)) sanitized else DefaultStates.PORT
        prefs.port.update(validValue)
    }
    fun updateSampleRate(value: SampleRates) = viewModelScope.launch { prefs.sampleRate.update(value) }
    fun updateChannelCount(value: ChannelCount) = viewModelScope.launch { prefs.channelCount.update(value) }
    fun updateAudioFormat(value: AudioFormat) = viewModelScope.launch { prefs.audioFormat.update(value) }
    fun updateAudioSource(value: AudioSource) = viewModelScope.launch { prefs.audioSource.update(value) }

    private fun sendCommand(what: Int) {
        try {
            val m = Message.obtain()
            m.what = what
            m.replyTo = responseMessenger
            service?.send(m)
        } catch (e: Exception) {
            Log.e("USBLinkMic", "send command failed", e)
            addLogMessage("与服务通信失败：${e.message}")
        }
    }

    private fun sendCommand(m: Message) {
        try {
            m.replyTo = responseMessenger
            service?.send(m)
        } catch (e: Exception) {
            Log.e("USBLinkMic", "send command failed", e)
            addLogMessage("与服务通信失败：${e.message}")
        }
    }

    private fun addLogMessage(message: String) {
        val lines = (textLog + message + "\n").lines().filter { it.isNotBlank() }.takeLast(120)
        textLog = lines.joinToString(separator = "\n", postfix = if (lines.isEmpty()) "" else "\n")
    }

    private fun appendWaveLevels(levels: List<Float>) {
        if (levels.isEmpty()) return
        val trimmed = if (levels.size > 48) levels.takeLast(48) else levels
        micWaveLevels = (micWaveLevels.drop(trimmed.size) + trimmed).takeLast(48)
    }

    override fun onCleared() {
        stopNetworkMonitoring()
        usbStatusJob?.cancel()
        usbStatusJob = null
        responseMessenger = null
        service = null
        super.onCleared()
    }
}
