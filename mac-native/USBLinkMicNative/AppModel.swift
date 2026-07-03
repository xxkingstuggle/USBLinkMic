import Foundation
import CoreAudio
import Network
import SwiftUI

struct NetworkAdapter: Identifiable, Hashable {
    let name: String
    let ip: String
    var id: String { "\(name)-\(ip)" }
}

@MainActor
final class AppModel: ObservableObject {
    enum ModuleState: Equatable {
        case off
        case starting
        case running
        case stopping
        case failed(String)

        var isOn: Bool {
            if case .running = self { return true }
            if case .starting = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .off: "已停止"
            case .starting: "启动中"
            case .running: "运行中"
            case .stopping: "停止中"
            case .failed: "异常"
            }
        }
    }

    struct NetworkSnapshot {
        var service = "未检测到"
        var device = "-"
        var ip = "-"
        var router = "-"
        var defaultRoute = "-"
        var usbFunction = "-"
    }

    @Published var micState: ModuleState = .off
    @Published var phoneToMacState: ModuleState = .off
    @Published var macToPhoneState: ModuleState = .off
    @Published var network = NetworkSnapshot()
    @Published var adbPath = "查找中"
    @Published var deviceSummary = "未检测"
    @Published var reverseSummary = "未检测"
    @Published var audioDevice = "系统默认输出"
    @Published var audioOutputDevices: [String] = ["系统默认输出"]
    @Published var audioPort = 54345
    @Published var micConnectionMode: MicConnectionMode = .adb
    @Published var micSampleRate = 44100
    @Published var micChannelCount = 1
    @Published var micAudioFormat = "i16"
    @Published var micAudioSource = "Mic"
    @Published var networkAdapters: [NetworkAdapter] = []
    @Published var selectedAdapter: NetworkAdapter? = nil
    @Published var defaultRouteInterface: String? = nil

    enum MicConnectionMode: String, CaseIterable, Identifiable {
        case adb = "adb"
        case wifi = "wifi"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .adb: return "ADB（推荐）"
            case .wifi: return "Wi-Fi TCP"
            }
        }

        var detail: String {
            switch self {
            case .adb: return "通过 USB 数据线 + ADB reverse 连接手机"
            case .wifi: return "手机和 Mac 在同一 Wi-Fi，手机手动连接 Mac IP"
            }
        }
    }
    @Published var micGain = 1.0
    @Published var micMuted = false
    var currentMicEndpoint: String {
        let ip = selectedAdapter?.ip ?? localIPv4Address() ?? "未知"
        return "\(ip):\(audioPort)"
    }
    @Published var dnsServers = "8.8.8.8"
    @Published var routes = "0.0.0.0/0"
    @Published var hasRealAudioSamples = false
    @Published var waveSamples: [(Float, Float)] = []
    @Published var logs: [String] = []
    @Published var sidebarCollapsed = false

    // 限制 UI 刷新频率，避免高频率音频包触发大量 SwiftUI 重组。
    // 这些属性由接收队列 + 波形队列访问，用 nonisolated(unsafe) 避免 MainActor 调度开销。
    nonisolated(unsafe) private var pendingWaveformUpdate = false
    private var pendingLogLines: [String] = []
    private var logFlushTask: Task<Void, Never>?
    nonisolated private let waveformQueue = DispatchQueue(label: "USBLinkMic.WaveformUI")
    /// 预分配的单声道浮点缓冲区，供音频包→波形转换复用，避免每包堆分配。
    nonisolated(unsafe) private var monoBuffer: [Float] = []
    /// 预分配的工作区缓冲区，供解码器格式转换复用，避免多声道模式下每包堆分配。
    nonisolated(unsafe) private var formatWorkspace: [Float] = []

    let relayPort = 31416
    let relaySocket = "usblinkmic_net"
    let androidPackage = "com.zjx.usblinkmic"
    let mainActivity = "io.github.teamclouday.androidMic.ui.MainActivity"
    let micService = "io.github.teamclouday.androidMic.domain.service.ForegroundService"
    let networkActivity = "io.github.teamclouday.androidMic.network.LinkNetActivity"
    private let micReceiver = MicReceiver()
    nonisolated private let audioPlayer = AudioPlayer()
    nonisolated private let waveformData = WaveformData(capacity: 160)
    private let defaults = UserDefaults.standard
    private var previousUsbFunctionBeforeNcm: String?
    private var phoneToMacOperationInProgress = false

    init() {
        audioDevice = defaults.string(forKey: "audioDevice") ?? "系统默认输出"
        let savedAudioPort = defaults.integer(forKey: "audioPort")
        audioPort = savedAudioPort > 0 ? savedAudioPort : 54345
        micConnectionMode = MicConnectionMode(rawValue: defaults.string(forKey: "micConnectionMode") ?? "") ?? .adb
        let savedSampleRate = defaults.integer(forKey: "micSampleRate")
        micSampleRate = savedSampleRate > 0 ? savedSampleRate : 44100
        let savedChannelCount = defaults.integer(forKey: "micChannelCount")
        micChannelCount = savedChannelCount > 0 ? savedChannelCount : 1
        micAudioFormat = defaults.string(forKey: "micAudioFormat") ?? "i16"
        micAudioSource = defaults.string(forKey: "micAudioSource") ?? "Mic"
        let savedGain = defaults.double(forKey: "micGain")
        micGain = savedGain > 0 ? savedGain : 1.0
        micMuted = defaults.bool(forKey: "micMuted")
        dnsServers = defaults.string(forKey: "dnsServers") ?? "8.8.8.8"
        routes = defaults.string(forKey: "routes") ?? "0.0.0.0/0"
        refreshAudioDevices()
        networkAdapters = listNetworkAdapters()
        restoreSelectedAdapter()
        Task { await refreshNetworkAdapters() }
    }

    var adbExecutable: String {
        let candidates = [
            ProcessInfo.processInfo.environment["ADB"],
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "adb"
    }

    var runningCount: Int {
        [micState.isOn, phoneToMacState.isOn, macToPhoneState.isOn].filter { $0 }.count
    }

    func refresh() async {
        adbPath = adbExecutable
        await refreshAdb()
        await refreshNetwork()
        appendLog("状态已刷新")
    }

    func toggleMic(_ isOn: Bool) async {
        isOn ? await startMic() : await stopMic()
    }

    func togglePhoneToMac(_ isOn: Bool) async {
        isOn ? await startPhoneToMac() : await stopPhoneToMac()
    }

    func toggleMacToPhone(_ isOn: Bool) async {
        isOn ? await startMacToPhone() : await stopMacToPhone()
    }

    func stopAll() async {
        await stopMic()
        await stopMacToPhone()
        await stopPhoneToMac()
        appendLog("全部模块已请求停止")
    }

    private func startMic() async {
        micState = .starting
        hasRealAudioSamples = false
        waveSamples.removeAll()
        waveformData.reset()
        appendLog("手机麦克风：开始启动 [\(micConnectionMode.label)]")
        do {
            try micReceiver.start(port: audioPort) { [weak self] event in
                // 在 MicReceiver 队列直接处理，避免每包都切到 MainActor 再切回来。
                self?.handleMicReceiverEvent(event)
            }
            appendLog("手机麦克风：Mac 接收端已监听 tcp:\(audioPort)")
        } catch {
            micState = .failed("Mac 接收端口启动失败")
            appendLog("手机麦克风启动失败：Mac 无法监听 tcp:\(audioPort)：\(error.localizedDescription)")
            return
        }

        do {
            let deviceID = audioDevice == "系统默认输出" ? nil : systemOutputDeviceID(named: audioDevice)
            let format = AudioSampleFormat.from(string: micAudioFormat) ?? .i16
            try audioPlayer.start(
                sampleRate: Double(micSampleRate),
                channelCount: micChannelCount,
                audioFormat: format,
                outputDeviceID: deviceID
            )
            audioPlayer.gain = Float(micGain)
            audioPlayer.isMuted = micMuted
            appendLog("手机麦克风：Mac 音频播放器已启动，采样率 \(micSampleRate) Hz")
        } catch {
            micReceiver.stop()
            micState = .failed("Mac 音频播放器启动失败：\(error.localizedDescription)")
            appendLog("手机麦克风启动失败：Mac 音频播放器启动失败：\(error.localizedDescription)")
            return
        }

        switch micConnectionMode {
        case .adb:
            await startMicAdb()
        case .wifi:
            await startMicWifi()
        }
    }

    private func startMicAdb() async {
        guard let serial = await selectedSerial() else {
            micReceiver.stop()
            audioPlayer.stop()
            micState = .failed("未检测到 ADB 设备")
            appendLog("手机麦克风启动失败：未检测到 ADB 设备")
            return
        }
        appendLog("手机麦克风：使用设备 \(serial)，准备 reverse tcp:\(audioPort)")
        let reverse = await adb(["-s", serial, "reverse", "tcp:\(audioPort)", "tcp:\(audioPort)"])
        appendLog("手机麦克风：adb reverse 状态 \(reverse.status)\(formatShellDetail(reverse))")
        let result = await adb([
            "-s", serial, "shell", "am", "start",
            "-a", "com.zjx.usblinkmic.START_MIC",
            "-n", "\(androidPackage)/\(mainActivity)",
            "--ez", "fromAdb", "true",
            "--ei", "port", "\(audioPort)",
            "--ei", "sampleRate", "\(micSampleRate)",
            "--ei", "channelCount", "\(micChannelCount)",
            "--es", "audioFormat", micAudioFormat,
            "--es", "audioSource", micAudioSource
        ])
        appendLog("手机麦克风：Android 服务启动状态 \(result.status)\(formatShellDetail(result))")
        if result.status == 0 {
            micState = .running
            appendLog("手机麦克风已启动")
        } else {
            micReceiver.stop()
            audioPlayer.stop()
            micState = .failed(result.mergedOutput)
            appendLog("手机麦克风启动失败：\(result.mergedOutput)")
        }
        await refreshAdb()
    }

    private func startMicWifi() async {
        await refreshNetworkAdapters()
        appendLog("手机麦克风：Wi-Fi 模式，请在 Android App 设置中连接 \(currentMicEndpoint)")
        micState = .running
    }

    private func stopMic() async {
        micState = .stopping
        hasRealAudioSamples = false
        waveSamples.removeAll()
        waveformData.reset()
        appendLog("手机麦克风：开始停止")
        micReceiver.stop()
        audioPlayer.stop()

        if micConnectionMode == .adb, let serial = await selectedSerial() {
            let stop = await adb([
                "-s", serial, "shell", "am", "start",
                "-a", "com.zjx.usblinkmic.STOP_MIC",
                "-n", "\(androidPackage)/\(mainActivity)",
                "--ez", "fromAdb", "true"
            ])
            appendLog("手机麦克风：Android 停止服务状态 \(stop.status)\(formatShellDetail(stop))")
            let remove = await adb(["-s", serial, "reverse", "--remove", "tcp:\(audioPort)"])
            appendLog("手机麦克风：移除 reverse 状态 \(remove.status)\(formatShellDetail(remove))")
        }

        micState = .off
        appendLog("手机麦克风已停止")
        await refreshAdb()
    }

    private func startPhoneToMac() async {
        phoneToMacOperationInProgress = true
        phoneToMacState = .starting
        defer { phoneToMacOperationInProgress = false }

        guard let serial = await selectedSerial() else {
            phoneToMacState = .failed("未检测到 ADB 设备")
            return
        }

        let before = await currentUsbFunction(serial: serial)

        // 如果已经是 NCM，不再重复下发 setFunctions，避免 ADB 断开的误报。
        if before.lowercased().contains("ncm") {
            await enablePhoneToMacNetworkService()
            await refreshNetworkWithRetry()
            if network.ip != "-" || network.usbFunction.lowercased().contains("ncm") {
                phoneToMacState = .running
                appendLog("手机网络给 Mac 已在运行：\(network.ip) / \(network.router)")
            } else {
                phoneToMacState = .failed("CDC-NCM 未拿到 IP")
                appendLog("手机网络给 Mac：NCM 已开启，未拿到 IP")
            }
            return
        }

        if !before.isEmpty {
            previousUsbFunctionBeforeNcm = before
        }

        // 先把 Mac 侧的网络服务启用，等 NCM 上来后 DHCP 才能拿到地址。
        await enablePhoneToMacNetworkService()

        appendLog("手机网络给 Mac：请求切换到 NCM…")
        let started = await setUsbFunctionExpectingDisconnect(serial: serial, function: "ncm")
        if !started {
            phoneToMacState = .failed("ADB 未发起 CDC-NCM 切换")
            appendLog("手机网络给 Mac 启动失败：ADB 未发起切换")
            return
        }

        // 等 USB gadget 重置、ADB 重连、Mac DHCP 拿地址。
        try? await Task.sleep(for: .seconds(5))
        await refreshNetworkWithRetry()

        // 只要 USB function 是 NCM 或 Mac 已经拿到手机网段的 IP，就认为成功。
        let usbIsNcm = network.usbFunction.lowercased().contains("ncm")
        if usbIsNcm || network.ip != "-" {
            phoneToMacState = .running
            appendLog("手机网络给 Mac 已启动：\(network.ip) / \(network.router)")
        } else {
            phoneToMacState = .failed("CDC-NCM 未拿到 IP")
            appendLog("手机网络给 Mac：未检测到 NCM 或 IP")
        }
    }

    private func stopPhoneToMac() async {
        phoneToMacOperationInProgress = true
        phoneToMacState = .stopping
        defer { phoneToMacOperationInProgress = false }

        // 先把 Mac 侧的网络服务禁用，让默认路由立即回到 Wi-Fi，
        // 即使 Android 端因为 ADB 断开没切回来，Mac 也不会走手机网络。
        await disablePhoneToMacNetworkService()

        guard let serial = await selectedSerial() else {
            await refreshNetworkWithRetry()
            phoneToMacState = .off
            appendLog("手机网络给 Mac 已停止（无 ADB 设备）")
            return
        }

        let before = await currentUsbFunction(serial: serial)
        if !before.lowercased().contains("ncm") {
            // 已经不是 NCM，不需要再发 setFunctions。
            previousUsbFunctionBeforeNcm = nil
            await refreshNetworkWithRetry()
            phoneToMacState = .off
            appendLog("手机网络给 Mac 已停止")
            return
        }

        let target = restoreUsbFunction()
        appendLog("手机网络给 Mac：请求从 NCM 恢复到 \(target)…")
        _ = await setUsbFunctionExpectingDisconnect(serial: serial, function: target)
        if target != "adb" {
            _ = await setUsbFunctionExpectingDisconnect(serial: serial, function: "adb")
        }

        previousUsbFunctionBeforeNcm = nil
        await refreshNetworkWithRetry()
        phoneToMacState = .off
        appendLog("手机网络给 Mac 已停止")
    }

    private func startMacToPhone() async {
        macToPhoneState = .starting
        guard let serial = await selectedSerial() else {
            macToPhoneState = .failed("未检测到 ADB 设备")
            return
        }
        let reverse = await adb(["-s", serial, "reverse", "localabstract:\(relaySocket)", "tcp:\(relayPort)"])
        let start = await adb([
            "-s", serial, "shell", "am", "start",
            "-a", "com.zjx.usblinkmic.START_NETWORK",
            "-n", "\(androidPackage)/\(networkActivity)",
            "--esa", "dnsServers", dnsServers,
            "--esa", "routes", routes
        ])
        if reverse.status == 0 && start.status == 0 {
            macToPhoneState = .running
            appendLog("Mac 网络给手机已请求启动")
        } else {
            macToPhoneState = .failed([reverse.mergedOutput, start.mergedOutput].joined(separator: "\n"))
        }
        await refreshAdb()
    }

    private func stopMacToPhone() async {
        macToPhoneState = .stopping
        if let serial = await selectedSerial() {
            _ = await adb([
                "-s", serial, "shell", "am", "start",
                "-a", "com.zjx.usblinkmic.STOP_NETWORK",
                "-n", "\(androidPackage)/\(networkActivity)"
            ])
            _ = await adb(["-s", serial, "reverse", "--remove", "localabstract:\(relaySocket)"])
        }
        macToPhoneState = .off
        appendLog("Mac 网络给手机已停止")
        await refreshAdb()
    }

    private func refreshAdb() async {
        let devices = await adb(["devices"])
        let reverse = await adb(["reverse", "--list"])
        deviceSummary = compact(devices.output)
        reverseSummary = compact(reverse.output)
    }

    private func refreshNetworkWithRetry(maxAttempts: Int = 3) async {
        for attempt in 1...maxAttempts {
            await refreshNetwork()
            let usbIsNcm = network.usbFunction.lowercased().contains("ncm")
            let hasIp = network.ip != "-"
            if usbIsNcm || hasIp {
                return
            }
            if attempt < maxAttempts {
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshNetwork() async {
        async let hardware = Shell.runPath("networksetup", ["-listallhardwareports"])
        async let route = Shell.runPath("route", ["-n", "get", "default"])
        async let usb = selectedSerial().flatMap { serial in
            Task { await self.adb(["-s", serial, "shell", "svc", "usb", "getFunctions"]) }
        }?.value

        let hardwareOutput = await hardware.output
        let defaultRoute = await parseDefaultRoute(route.output)
        let ports = parseHardwarePorts(hardwareOutput)

        var best = NetworkSnapshot(defaultRoute: defaultRoute, usbFunction: (await usb?.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "-")
        for port in ports {
            let info = await Shell.runPath("networksetup", ["-getinfo", port.name]).output
            let ip = parseValue(info, prefix: "IP address:") ?? "-"
            let router = parseValue(info, prefix: "Router:") ?? "-"
            let lower = port.name.lowercased()
            let looksPhone = ["android", "redmi", "xiaomi", "pixel", "samsung", "huawei", "honor", "oppo", "vivo", "realme", "oneplus", "motorola", "nothing"].contains { lower.contains($0) }
            let privateRouter = router.hasPrefix("10.") || router.hasPrefix("192.168.") || router.hasPrefix("172.")
            if looksPhone || privateRouter {
                best.service = port.name
                best.device = port.device
                best.ip = ip
                best.router = router
                if port.device == defaultRoute || best.ip != "-" {
                    break
                }
            }
        }
        network = best

        // 当用户正在手动切换 CDC-NCM 时，不拿检测结果覆盖开关状态，
        // 避免开关弹回，造成“假开关”的感觉。
        if !phoneToMacOperationInProgress {
            let usbIsNcm = best.usbFunction.lowercased().contains("ncm")
            let hasPhoneIp = best.ip != "-"
            phoneToMacState = (usbIsNcm || hasPhoneIp) ? .running : .off
        }
    }

    private func currentUsbFunction(serial: String) async -> String {
        let result = await adb(["-s", serial, "shell", "svc", "usb", "getFunctions"])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restoreUsbFunction() -> String {
        let previous = previousUsbFunctionBeforeNcm?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let previous, !previous.isEmpty, previous != "ncm" {
            return previous
        }
        return "mtp,adb"
    }

    private func setUsbFunctionExpectingDisconnect(serial: String, function: String) async -> Bool {
        let result = await adb(["-s", serial, "shell", "svc", "usb", "setFunctions", function])
        let combined = (result.output + "\n" + result.error).lowercased()
        // setFunctions 会重置 USB gadget，ADB 会断，shell 被 SIGKILL（exit 137）。
        // 只要输出里出现 setCurrentFunctions，就说明指令已下发到 Android USB 服务。
        if result.status == 0 || combined.contains("setcurrentfunctions") {
            return true
        }
        appendLog("切换 USB function 到 \(function) 失败：\(result.mergedOutput)")
        return false
    }

    private func disablePhoneToMacNetworkService() async {
        let hardwareOutput = await Shell.runPath("networksetup", ["-listallhardwareports"]).output
        let ports = parseHardwarePorts(hardwareOutput)
        for port in ports where isPhoneLikeServiceName(port.name) {
            _ = await Shell.runPath("networksetup", ["-setnetworkserviceenabled", port.name, "off"])
            appendLog("已禁用 Mac 网络服务：\(port.name)")
        }
    }

    private func enablePhoneToMacNetworkService() async {
        let hardwareOutput = await Shell.runPath("networksetup", ["-listallhardwareports"]).output
        let ports = parseHardwarePorts(hardwareOutput)
        for port in ports where isPhoneLikeServiceName(port.name) {
            _ = await Shell.runPath("networksetup", ["-setnetworkserviceenabled", port.name, "on"])
            appendLog("已启用 Mac 网络服务：\(port.name)")
        }
    }

    private func isPhoneLikeServiceName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["android", "redmi", "xiaomi", "pixel", "samsung", "huawei", "honor",
                "oppo", "vivo", "realme", "oneplus", "motorola", "nothing", "ncm"]
            .contains { lower.contains($0) }
    }

    private func selectedSerial() async -> String? {
        let result = await adb(["devices"])
        return result.output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> String? in
                let parts = line.split(separator: "\t")
                return parts.count >= 2 && parts[1] == "device" ? String(parts[0]) : nil
            }
            .first
    }

    private func adb(_ arguments: [String]) async -> ShellResult {
        if adbExecutable == "adb" {
            await Shell.runPath("adb", arguments)
        } else {
            await Shell.run(adbExecutable, arguments)
        }
    }

    private func appendLog(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        let line = "[\(stamp)] \(message)"
        pendingLogLines.append(line)
        flushLogsIfNeeded()
    }

    private func flushLogsIfNeeded() {
        guard logFlushTask == nil else { return }
        logFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            self.logFlushTask = nil
            if self.pendingLogLines.isEmpty { return }
            self.logs.append(contentsOf: self.pendingLogLines)
            self.pendingLogLines.removeAll()
            if self.logs.count > 80 {
                self.logs.removeFirst(self.logs.count - 80)
            }
        }
    }

    private func compact(_ text: String) -> String {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return lines.prefix(3).joined(separator: " / ").isEmpty ? "无" : lines.prefix(3).joined(separator: " / ")
    }

    private func formatShellDetail(_ result: ShellResult) -> String {
        let detail = result.mergedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return ""
        }
        return "：\(compact(detail))"
    }

    nonisolated private func handleMicReceiverEvent(_ event: MicReceiverEvent) {
        switch event {
        case .status(let message):
            Task { @MainActor [weak self] in
                if message.contains("音频包") {
                    self?.hasRealAudioSamples = true
                }
                self?.appendLog("手机麦克风：\(message)")
            }
        case .packet(let packet):
            let t0 = perfNow()
            audioPlayer.write(packet: packet)
            if let format = AudioSampleFormat(rawValue: packet.audioFormat) {
                format.interleavedBytesToMonoFloat(packet.buffer, channelCount: Int(packet.channelCount), into: &monoBuffer, workspace: &formatWorkspace)
                let t1 = perfNow()
                waveformData.append(samples: monoBuffer, sampleRate: Double(packet.sampleRate))
                let t2 = perfNow()
                sharedPerfTracer.record("packet.bytesToMono", nanos: t1 - t0)
                sharedPerfTracer.record("packet.waveform", nanos: t2 - t1)
                scheduleWaveformUpdate()
            }
        }
    }

    nonisolated private func scheduleWaveformUpdate() {
        guard !pendingWaveformUpdate else { return }
        pendingWaveformUpdate = true
        // 降到 ~20 Hz，与 Rust 原项目的低刷新开销一致。
        waveformQueue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            guard let self else { return }
            let samples = self.waveformData.read()
            Task { @MainActor [weak self] in
                self?.waveSamples = samples
                self?.pendingWaveformUpdate = false
            }
        }
    }

    func refreshAudioDevices() {
        let devices = systemOutputDevices()
        audioOutputDevices = ["系统默认输出"] + devices.map { $0.name }.filter { $0 != "系统默认输出" }
        if !audioOutputDevices.contains(audioDevice) {
            audioDevice = audioOutputDevices.first ?? "系统默认输出"
            defaults.set(audioDevice, forKey: "audioDevice")
        }
        appendLog("音频输出设备已刷新：\(audioOutputDevices.count) 个")
    }

    private func systemOutputDeviceID(named: String) -> AudioDeviceID? {
        return systemOutputDevices().first { $0.name == named }?.id
    }

    func saveSettings() {
        defaults.set(audioDevice, forKey: "audioDevice")
        defaults.set(audioPort, forKey: "audioPort")
        defaults.set(micConnectionMode.rawValue, forKey: "micConnectionMode")
        defaults.set(micSampleRate, forKey: "micSampleRate")
        defaults.set(micChannelCount, forKey: "micChannelCount")
        defaults.set(micAudioFormat, forKey: "micAudioFormat")
        defaults.set(micAudioSource, forKey: "micAudioSource")
        defaults.set(micGain, forKey: "micGain")
        defaults.set(micMuted, forKey: "micMuted")
        defaults.set(dnsServers, forKey: "dnsServers")
        defaults.set(routes, forKey: "routes")
        defaults.set(selectedAdapter?.ip, forKey: "selectedAdapterIP")
        appendLog("设置已保存")
        // 如果手机麦克风正在运行，仅重新初始化 Mac 音频播放器以应用新的输出设备/音频参数，
        // 不需要断开手机到 Mac 的网络连接。
        if micState.isOn {
            restartAudioPlayer()
        }
    }

    /// 仅重新初始化 Mac 音频播放器，用于切换输出设备或音频参数时不中断手机到 Mac 的网络连接。
    private func restartAudioPlayer() {
        let deviceID = audioDevice == "系统默认输出" ? nil : systemOutputDeviceID(named: audioDevice)
        let format = AudioSampleFormat.from(string: micAudioFormat) ?? .i16
        do {
            try audioPlayer.start(
                sampleRate: Double(micSampleRate),
                channelCount: micChannelCount,
                audioFormat: format,
                outputDeviceID: deviceID
            )
            audioPlayer.gain = Float(micGain)
            audioPlayer.isMuted = micMuted
            appendLog("手机麦克风：Mac 音频输出已切换到 \(audioDevice)")
        } catch {
            appendLog("手机麦克风：Mac 音频输出切换失败：\(error.localizedDescription)")
        }
    }

    func selectAdapter(_ adapter: NetworkAdapter) {
        selectedAdapter = adapter
        defaults.set(adapter.ip, forKey: "selectedAdapterIP")
    }

    func refreshNetworkAdapters() async {
        let adapters = listNetworkAdapters()
        let route = await defaultRouteInterfaceName()
        await MainActor.run {
            networkAdapters = adapters
            defaultRouteInterface = route
            if let current = selectedAdapter,
               let adapter = adapters.first(where: { $0.id == current.id }) {
                selectedAdapter = adapter
            } else if let savedIP = defaults.string(forKey: "selectedAdapterIP"),
                      let adapter = adapters.first(where: { $0.ip == savedIP }) {
                selectedAdapter = adapter
            } else if let route,
                      let adapter = adapters.first(where: { $0.name == route }) {
                selectedAdapter = adapter
            } else {
                selectedAdapter = adapters.first
            }
        }
    }

    private func restoreSelectedAdapter() {
        let savedIP = defaults.string(forKey: "selectedAdapterIP")
        if let savedIP, let adapter = networkAdapters.first(where: { $0.ip == savedIP }) {
            selectedAdapter = adapter
        } else if let adapter = networkAdapters.first {
            selectedAdapter = adapter
        }
    }

    private func listNetworkAdapters() -> [NetworkAdapter] {
        var adapters: [NetworkAdapter] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return adapters }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = ptr {
            let name = String(cString: iface.pointee.ifa_name)
            let flags = Int32(iface.pointee.ifa_flags)
            if let addr = iface.pointee.ifa_addr,
               addr.pointee.sa_family == AF_INET,
               (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    adapters.append(NetworkAdapter(name: name, ip: ip))
                }
            }
            ptr = iface.pointee.ifa_next
        }
        return adapters
    }

    private func defaultRouteInterfaceName() async -> String? {
        let result = await Shell.runPath("route", ["-n", "get", "default"])
        return result.output
            .split(separator: "\n")
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") }
            .flatMap { $0.split(separator: ":").last }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private func systemOutputDevices() -> [(name: String, id: AudioDeviceID)] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else {
        return []
    }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var devices = Array(repeating: AudioDeviceID(), count: count)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &devices) == noErr else {
        return []
    }

    return devices.compactMap { deviceID in
        guard deviceHasOutputStreams(deviceID), let name = audioDeviceName(deviceID) else {
            return nil
        }
        return (name, deviceID)
    }.sorted { $0.name < $1.name }
}

private func deviceHasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr && dataSize > 0
}

private func audioDeviceName(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var dataSize = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) { pointer in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
    }
    return status == noErr ? String(name) : nil
}

private func parseDefaultRoute(_ output: String) -> String {
    output.split(separator: "\n")
        .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") }
        .flatMap { $0.split(separator: ":").last }
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "-"
}

private func parseValue(_ output: String, prefix: String) -> String? {
    output.split(separator: "\n")
        .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
        .map { String($0).replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

private func parseHardwarePorts(_ output: String) -> [(name: String, device: String)] {
    var result: [(name: String, device: String)] = []
    var currentName: String?
    for line in output.split(separator: "\n").map(String.init) {
        if line.hasPrefix("Hardware Port: ") {
            currentName = String(line.dropFirst("Hardware Port: ".count))
        } else if line.hasPrefix("Device: "), let name = currentName {
            result.append((name, String(line.dropFirst("Device: ".count))))
            currentName = nil
        }
    }
    return result
}

private func defaultRouteInterfaceNameSync() -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/route")
    process.arguments = ["-n", "get", "default"]
    process.standardOutput = pipe
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.split(separator: "\n")
        .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") }
        .flatMap { $0.split(separator: ":").last }
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
}

private func localIPv4Address() -> String? {
    guard let defaultRoute = defaultRouteInterfaceNameSync() else { return nil }
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let iface = ptr {
        let name = String(cString: iface.pointee.ifa_name)
        guard name == defaultRoute,
              let addr = iface.pointee.ifa_addr,
              addr.pointee.sa_family == AF_INET else {
            ptr = iface.pointee.ifa_next
            continue
        }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            return String(cString: host)
        }
        ptr = iface.pointee.ifa_next
    }
    return nil
}

enum MicReceiverEvent: @unchecked Sendable {
    case status(String)
    case packet(AudioPacketMessage)
}

final class MicReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "USBLinkMic.MicReceiver")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var packetCount = 0
    private var byteCount = 0

    func start(port: Int, onEvent: @escaping @Sendable (MicReceiverEvent) -> Void) throws {
        stop()
        packetCount = 0
        byteCount = 0

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "USBLinkMic.MicReceiver", code: 1, userInfo: [NSLocalizedDescriptionKey: "端口无效"])
        }

        let listener = try NWListener(using: .tcp, on: nwPort)
        self.listener = listener
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                onEvent(.status("等待手机连接 tcp:\(port)"))
            case .failed(let error):
                onEvent(.status("接收端异常：\(error.localizedDescription)"))
            case .cancelled:
                onEvent(.status("接收端已停止"))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, onEvent: onEvent)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        packetCount = 0
        byteCount = 0
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }

    private func accept(_ connection: NWConnection, onEvent: @escaping @Sendable (MicReceiverEvent) -> Void) {
        connections.append(connection)
        onEvent(.status("手机已连接，等待握手"))
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                onEvent(.status("连接异常：\(error.localizedDescription)"))
                self?.removeConnection(connection)
            case .cancelled:
                onEvent(.status("连接已关闭"))
                self?.removeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveHandshake(connection, onEvent: onEvent)
    }

    private func receiveHandshake(_ connection: NWConnection, onEvent: @escaping @Sendable (MicReceiverEvent) -> Void) {
        connection.receive(minimumIncompleteLength: 11, maximumLength: 11) { [weak self] data, _, _, error in
            if let error {
                onEvent(.status("握手读取失败：\(error.localizedDescription)"))
                connection.cancel()
                return
            }
            guard let data, String(data: data, encoding: .utf8) == "AndroidMic1" else {
                onEvent(.status("握手失败：不是 AndroidMic 协议"))
                connection.cancel()
                return
            }

            guard let receiver = self else { return }
            connection.send(content: Data("AndroidMic2".utf8), completion: .contentProcessed { error in
                if let error {
                    onEvent(.status("握手响应失败：\(error.localizedDescription)"))
                    connection.cancel()
                    return
                }
                onEvent(.status("握手完成，开始接收音频"))
                receiver.receiveHeader(connection, onEvent: onEvent)
            })
        }
    }

    private func receiveHeader(_ connection: NWConnection, onEvent: @escaping @Sendable (MicReceiverEvent) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                onEvent(.status("音频头读取失败：\(error.localizedDescription)"))
                connection.cancel()
                return
            }
            if isComplete && (data?.isEmpty ?? true) {
                onEvent(.status("手机停止发送音频"))
                connection.cancel()
                return
            }
            guard let data, data.count == 4 else {
                onEvent(.status("音频头不完整"))
                connection.cancel()
                return
            }

            let length = data.reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= 4 * 1024 * 1024 else {
                onEvent(.status("音频包长度异常：\(length)"))
                connection.cancel()
                return
            }
            self.receiveBody(connection, length: length, onEvent: onEvent)
        }
    }

    private func receiveBody(_ connection: NWConnection, length: Int, onEvent: @escaping @Sendable (MicReceiverEvent) -> Void) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                onEvent(.status("音频包读取失败：\(error.localizedDescription)"))
                connection.cancel()
                return
            }
            guard let data, data.count == length else {
                onEvent(.status("音频包不完整"))
                connection.cancel()
                return
            }

            do {
                let packet = try decodeAudioPacketMessage(data)
                packetCount += 1
                byteCount += data.count
                if packetCount == 1 || packetCount % 50 == 0 {
                    onEvent(.status("收到真实音频包 \(packetCount) 个，\(byteCount / 1024) KB"))
                }
                onEvent(.packet(packet))
            } catch {
                onEvent(.status("音频包解析失败：\(error)"))
                connection.cancel()
                return
            }

            receiveHeader(connection, onEvent: onEvent)
        }
    }
}
