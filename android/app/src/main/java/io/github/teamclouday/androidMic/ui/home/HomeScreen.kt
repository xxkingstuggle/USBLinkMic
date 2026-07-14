package io.github.teamclouday.androidMic.ui.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.teamclouday.androidMic.AudioFormat
import io.github.teamclouday.androidMic.AudioSource
import io.github.teamclouday.androidMic.ChannelCount
import io.github.teamclouday.androidMic.Mode
import io.github.teamclouday.androidMic.SampleRates
import io.github.teamclouday.androidMic.ui.MainViewModel
import kotlin.math.sqrt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(vm: MainViewModel, requestPermissions: (() -> Unit) -> Unit) {
    LaunchedEffect(Unit) { vm.bindCheck() }
    DisposableEffect(Unit) {
        vm.startNetworkMonitoring()
        onDispose { vm.stopNetworkMonitoring() }
    }
    var showSettings by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("USB LinkMic", fontWeight = FontWeight.SemiBold) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Spacer(Modifier.height(8.dp))

            val running = vm.isStreamStarted || vm.isNetworkStarted
            val statusText = when {
                vm.isStreamStarted && vm.isNetworkStarted -> "全部运行中"
                vm.isStreamStarted -> buildString {
                    append("麦克风运行中")
                    if (vm.controlledByMac) append(" · 由 Mac 控制")
                    vm.activeMode?.let { append(" · ${it.name}") }
                }
                vm.isNetworkStarted -> "Mac 网络运行中"
                else -> "已就绪"
            }
            AssistChip(
                onClick = {},
                label = { Text(statusText) },
                leadingIcon = { Icon(Icons.Filled.Circle, null, Modifier.size(10.dp),
                    tint = if (running) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline) }
            )

            // Mic card
            Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Mic, null, tint = if (vm.isStreamStarted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("手机麦克风", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text("安卓麦克风输入到 Mac", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        IconButton(onClick = { showSettings = true }) {
                            Icon(Icons.Outlined.Settings, contentDescription = "麦克风设置")
                        }
                        val mode by vm.prefs.mode.getAsState()
                        if (mode == Mode.ADB) {
                            Icon(if (vm.isStreamStarted) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null,
                                tint = if (vm.isStreamStarted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                        } else {
                            Switch(checked = vm.isStreamStarted, onCheckedChange = { on ->
                                if (on) requestPermissions { vm.connect { } }
                                else vm.disconnect()
                            })
                        }
                    }
                    if (vm.isStreamStarted) {
                        HorizontalDivider()
                        LiveWaveform(
                            levels = vm.micWaveLevels,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(72.dp)
                        )
                        val sr = vm.activeSampleRate?.value ?: vm.prefs.sampleRate.getAsState().value.value
                        val ch = vm.activeChannelCount?.let { if (it == ChannelCount.Mono) "单声道" else "立体声" }
                            ?: when (vm.prefs.channelCount.getAsState().value) { ChannelCount.Mono -> "单声道" else -> "立体声" }
                        val fmt = vm.activeAudioFormat?.description ?: vm.prefs.audioFormat.getAsState().value.description
                        Text(
                            text = if (vm.controlledByMac) "由 Mac 控制 · $sr Hz · $ch · $fmt"
                                   else "$sr Hz · $ch · $fmt",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            // CDC-NCM status (read-only)
            Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.SettingsEthernet, null, tint = if (vm.isPhoneToMacUsbActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("手机网络给 Mac", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text("CDC-NCM 有线供网", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Icon(if (vm.isPhoneToMacUsbActive) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null,
                            tint = if (vm.isPhoneToMacUsbActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                    }
                    if (vm.isPhoneToMacUsbActive) {
                        HorizontalDivider()
                        Text(vm.phoneToMacUsbStatus, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            // Mac-to-Phone relay
            Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Outlined.SwapHoriz,
                            null,
                            tint = if (vm.isNetworkStarted || vm.isNetworkConnecting) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            }
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("Mac 网络给手机", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text("由 Mac 控制 · ADB VPN", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Icon(
                            when {
                                vm.isNetworkStarted -> Icons.Filled.CheckCircle
                                vm.isNetworkConnecting -> Icons.Filled.Sync
                                else -> Icons.Outlined.Circle
                            },
                            contentDescription = null,
                            tint = if (vm.isNetworkStarted || vm.isNetworkConnecting) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.outline
                            }
                        )
                    }
                    HorizontalDivider()
                    Text(vm.macToPhoneStatus, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        if (vm.isNetworkStarted) {
                            "relay tcp:31416 · usblinkmic_net"
                        } else {
                            "请在 Mac 端 USB LinkMic 打开“Mac 网络给手机”"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Log
            Card(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row { Text("诊断日志", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)); TextButton(onClick = { vm.cleanLog() }) { Text("清除") } }
                    Text(vm.textLog.ifEmpty { "日志将在此显示…" }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.heightIn(max = 200.dp))
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(onClick = { vm.refreshPhoneToMacUsbStatus() }, modifier = Modifier.fillMaxWidth()) { Text("刷新状态") }
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }

    if (showSettings) {
        SettingsDialog(vm = vm, onDismiss = { showSettings = false })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsDialog(vm: MainViewModel, onDismiss: () -> Unit) {
    val mode by vm.prefs.mode.getAsState()
    val ip by vm.prefs.ip.getAsState()
    val port by vm.prefs.port.getAsState()
    val sampleRate by vm.prefs.sampleRate.getAsState()
    val channelCount by vm.prefs.channelCount.getAsState()
    val audioFormat by vm.prefs.audioFormat.getAsState()
    val audioSource by vm.prefs.audioSource.getAsState()

    var ipInput by remember { mutableStateOf(ip) }
    var portInput by remember { mutableStateOf(port) }

    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("完成") }
        },
        title = { Text("设置") },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text("手机麦克风", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                val supportedModes = remember { listOf(Mode.ADB, Mode.WIFI) }
                EnumMenu(
                    label = "协议",
                    value = mode,
                    values = supportedModes,
                    display = {
                        when (it) {
                            Mode.ADB -> "ADB（已支持）"
                            Mode.WIFI -> "Wi-Fi TCP"
                            Mode.UDP -> "UDP（暂不支持）"
                            Mode.USB -> "USB 有线（暂不支持）"
                        }
                    },
                    onSelect = vm::updateMode
                )
                Text(
                    text = when (mode) {
                        Mode.ADB -> "通过 USB 数据线连接 Mac。请在 Mac 端点击「手机麦克风」开关启动。"
                        Mode.WIFI -> "手机和 Mac 需连接同一 Wi-Fi，并填写 Mac 的局域网 IP。"
                        Mode.UDP, Mode.USB -> "当前版本暂不支持此模式。"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (mode == Mode.WIFI) {
                    OutlinedTextField(
                        value = ipInput,
                        onValueChange = {
                            ipInput = it
                            vm.updateIp(it)
                        },
                        label = { Text("Mac IP") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                OutlinedTextField(
                    value = portInput,
                    onValueChange = {
                        portInput = it
                        vm.updatePort(it)
                    },
                    label = { Text("端口") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                EnumMenu("采样率", sampleRate, SampleRates.entries, { "${it.value} Hz" }, vm::updateSampleRate)
                EnumMenu("声道", channelCount, ChannelCount.entries, {
                    when (it) {
                        ChannelCount.Mono -> "单声道"
                        ChannelCount.Stereo -> "立体声"
                    }
                }, vm::updateChannelCount)
                EnumMenu("音频格式", audioFormat, AudioFormat.entries, { it.description }, vm::updateAudioFormat)
                EnumMenu("音频源", audioSource, AudioSource.entries, {
                    when (it) {
                        AudioSource.Mic -> "Mic"
                        AudioSource.Recognition -> "Recognition"
                        AudioSource.Communication -> "Communication"
                        AudioSource.Performance -> "Performance"
                    }
                }, vm::updateAudioSource)
            }
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> EnumMenu(
    label: String,
    value: T,
    values: List<T>,
    display: (T) -> String,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = display(value),
            onValueChange = {},
            label = { Text(label) },
            readOnly = true,
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
                .fillMaxWidth()
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            values.forEach { item ->
                DropdownMenuItem(
                    text = { Text(display(item)) },
                    onClick = {
                        onSelect(item)
                        expanded = false
                    }
                )
            }
        }
    }
}

@Composable
private fun LiveWaveform(levels: List<Float>, modifier: Modifier = Modifier) {
    val primary = MaterialTheme.colorScheme.primary
    val baseline = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.22f)
    Canvas(modifier = modifier) {
        val midY = size.height / 2f
        drawLine(
            color = baseline,
            start = Offset(0f, midY),
            end = Offset(size.width, midY),
            strokeWidth = 1.dp.toPx(),
            cap = StrokeCap.Round
        )
        if (levels.isEmpty()) return@Canvas
        val gap = 3.dp.toPx()
        val barWidth = ((size.width - gap * (levels.size - 1)) / levels.size).coerceAtLeast(2.dp.toPx())
        levels.forEachIndexed { index, raw ->
            val level = (sqrt(raw.coerceIn(0f, 1f)) * 1.35f).coerceIn(0f, 1f)
            val barHeight = (size.height * (0.12f + level * 0.88f)).coerceAtLeast(3.dp.toPx())
            val x = index * (barWidth + gap)
            drawRoundRect(
                color = primary.copy(alpha = 0.35f + level * 0.55f),
                topLeft = Offset(x, midY - barHeight / 2f),
                size = Size(barWidth, barHeight),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(barWidth / 2f, barWidth / 2f)
            )
        }
    }
}
