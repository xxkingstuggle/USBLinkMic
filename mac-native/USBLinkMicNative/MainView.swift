import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // 使用 contentBackground 材质，比 hudWindow 更轻量。
            VisualEffectView(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            content
        }
        .ignoresSafeArea(.all, edges: .top)
        .preferredColorScheme(nil)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.2)
            dashboard
        }
        .background(
            // 用静态背景色替代多层材质叠加；效果一致但 GPU 合成压力更小。
            colorScheme == .dark
                ? Color.black.opacity(0.12)
                : Color.white.opacity(0.18)
        )
    }

    private var sidebar: some View {
        Group {
            if model.sidebarCollapsed {
                collapsedSidebar
            } else {
                expandedSidebar
            }
        }
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Color.clear.frame(width: 72, height: 32) // Reduced from 80 to 72 to account for 8pt internal SF Symbol padding
                Button {
                    withAnimation(.snappy) { model.sidebarCollapsed.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.leading, -22)
            .padding(.top, 0) // Moved down by another 0.5 points
            
            VStack(alignment: .leading, spacing: 2) {
                Text("USB LinkMic")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Mac 控制面板")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16) // Compensate for the 0.5pt adjustment above

            expandedControls
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private var collapsedSidebar: some View {
        VStack(spacing: 18) {
            Color.clear
                .frame(height: 52)

            Button {
                withAnimation(.snappy) { model.sidebarCollapsed.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            collapsedControls
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
        .frame(width: 82)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private var expandedControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            StatusCapsule(text: model.runningCount > 0 ? "运行中" : "就绪", active: model.runningCount > 0)

            VStack(alignment: .leading, spacing: 10) {
                Text("核心开关")
                    .font(.headline)
                ControlRow(
                    icon: "mic.fill",
                    title: "手机麦克风",
                    subtitle: "安卓麦克风输入到 Mac",
                    state: model.micState,
                    isOn: Binding(
                        get: { model.micState.isOn },
                        set: { value in Task { await model.toggleMic(value) } }
                    )
                )
                ControlRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "手机网络给 Mac",
                    subtitle: "USB / CDC-NCM 有线供网",
                    state: model.phoneToMacState,
                    infoTooltip: "切换前请保持手机屏幕点亮并解锁，锁屏会阻止 USB 功能切换",
                    isOn: Binding(
                        get: { model.phoneToMacState.isOn },
                        set: { value in Task { await model.togglePhoneToMac(value) } }
                    )
                )
                ControlRow(
                    icon: "arrow.left.arrow.right",
                    title: "Mac 网络给手机",
                    subtitle: "ADB VPN 反向转发",
                    state: model.macToPhoneState,
                    isOn: Binding(
                        get: { model.macToPhoneState.isOn },
                        set: { value in Task { await model.toggleMacToPhone(value) } }
                    )
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("快速操作")
                    .font(.headline)
                Button(action: { Task { await model.refresh() } }) {
                    Text("刷新状态")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                
                Button(action: { Task { await model.stopAll() } }) {
                    Text("全部停止")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

        }
    }

    private var collapsedControls: some View {
        VStack(spacing: 16) {
            IconToggle(symbol: "mic.fill", active: model.micState.isOn) {
                Task { await model.toggleMic(!model.micState.isOn) }
            }
            IconToggle(symbol: "antenna.radiowaves.left.and.right", active: model.phoneToMacState.isOn) {
                Task { await model.togglePhoneToMac(!model.phoneToMacState.isOn) }
            }
            IconToggle(symbol: "arrow.left.arrow.right", active: model.macToPhoneState.isOn) {
                Task { await model.toggleMacToPhone(!model.macToPhoneState.isOn) }
            }
            Spacer()
        }
    }

    private var dashboard: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 28) {
                Color.clear.frame(height: 24)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("运行状态")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("已开启 \(model.runningCount)/3 个模块")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("刷新") { Task { await model.refresh() } }
                }
                .padding(22)
                .glassPanel()

                VStack(spacing: 28) {
                    HStack(spacing: 28) {
                        MicPanel(showingSettings: $showingSettings)
                            .statusCardFrame()
                        PhoneNetworkPanel()
                            .statusCardFrame()
                    }

                    HStack(spacing: 28) {
                        MacRelayPanel()
                            .statusCardFrame()
                        DevicePanel()
                            .statusCardFrame()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

                LogPanel()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black.opacity(0.18), Color.blue.opacity(0.08)]
                    : [Color.white.opacity(0.25), Color.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let sampleRates = [8000, 11025, 16000, 22050, 44100, 48000, 88200, 96000, 176400, 192000]
    private let audioFormats = ["i16", "u8", "f32"]
    private let audioSources = ["Mic", "Recognition", "Communication", "Performance"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("音频、端口和网络转发参数")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(22)

            Divider()

            Form {
                Section("音频输出") {
                    Picker("输出设备", selection: $model.audioDevice) {
                        ForEach(model.audioOutputDevices, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }

                    Button("刷新输出设备") {
                        model.refreshAudioDevices()
                    }
                }

                Section("手机麦克风") {
                    Picker("连接模式", selection: $model.micConnectionMode) {
                        ForEach(AppModel.MicConnectionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Text(model.micConnectionMode.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.micConnectionMode == .wifi {
                        Section("网络接口") {
                            Button("刷新网络接口") {
                                Task { await model.refreshNetworkAdapters() }
                            }

                            Picker("选择接口", selection: $model.selectedAdapter) {
                                ForEach(model.networkAdapters) { adapter in
                                    Text(adapterLabel(adapter, defaultRoute: model.defaultRouteInterface))
                                        .tag(adapter as NetworkAdapter?)
                                }
                            }

                            HStack(spacing: 10) {
                                Text("Mac 端点")
                                Spacer()
                                Text(model.currentMicEndpoint)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                CopyButton(text: model.currentMicEndpoint)
                            }

                            Text("请确保手机和 Mac 在同一 Wi-Fi，然后在 Android App 设置中输入上面的 IP 和端口。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: model.selectedAdapter) { adapter in
                            if let adapter {
                                model.selectAdapter(adapter)
                            }
                        }
                    }

                    Picker("端口", selection: $model.audioPort) {
                        Text("54345 默认").tag(54345)
                        Text("54346").tag(54346)
                        Text("54347").tag(54347)
                    }

                    if model.micConnectionMode == .adb {
                        Picker("采样率", selection: $model.micSampleRate) {
                            ForEach(sampleRates, id: \.self) { rate in
                                Text("\(rate) Hz").tag(rate)
                            }
                        }

                        Picker("声道", selection: $model.micChannelCount) {
                            Text("单声道").tag(1)
                            Text("立体声").tag(2)
                        }

                        Picker("音频格式", selection: $model.micAudioFormat) {
                            ForEach(audioFormats, id: \.self) { format in
                                Text(format).tag(format)
                            }
                        }

                        Picker("音频源", selection: $model.micAudioSource) {
                            ForEach(audioSources, id: \.self) { source in
                                Text(source).tag(source)
                            }
                        }
                    } else {
                        Text("Wi-Fi 模式下，采样率、声道、格式和音频源由 Android 端设置控制。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("静音启动", isOn: $model.micMuted)

                    HStack {
                        Text("增益")
                        Slider(value: $model.micGain, in: 0.5...4.0, step: 0.1)
                        Text(String(format: "%.1fx", model.micGain))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Section("Mac 网络给手机") {
                    LabeledContent("Relay 端口", value: "\(model.relayPort)")
                    TextField("DNS", text: $model.dnsServers)
                    TextField("路由", text: $model.routes)
                }

                Section("说明") {
                    Text("ADB 模式下，Mac 会自动通过 USB 数据线启动手机服务；Wi-Fi TCP 模式下，需要手动在 Android App 设置里输入 Mac 的局域网 IP 和端口。这些设置会保存到本机。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 520, height: 640)
        .onDisappear {
            model.saveSettings()
        }
    }
}

private struct ControlRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let state: AppModel.ModuleState
    var infoTooltip: String? = nil
    @Binding var isOn: Bool
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(isOn ? Color.cyan.opacity(0.24) : Color.secondary.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                    if let infoTooltip {
                        Button {
                            showingInfo.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingInfo, arrowEdge: .trailing) {
                            Text(infoTooltip)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(width: 220, alignment: .leading)
                        }
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(isOn ? Color.cyan.opacity(0.18) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isOn ? Color.cyan.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct StatusCapsule: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(active ? Color.cyan.opacity(0.32) : Color.secondary.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
    }
}

private struct IconToggle: View {
    let symbol: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(active ? Color.cyan.opacity(0.32) : Color.secondary.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct MicPanel: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelHeader(title: "手机麦克风", state: model.micState)
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            WaveformView(samples: model.waveSamples)
                .frame(height: 122)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.hasRealAudioSamples ? "输出设备：\(model.audioDevice)" : "等待真实音频输入")
                HStack(spacing: 6) {
                    Text("模式：\(model.micConnectionMode.label)")
                    if model.micConnectionMode == .wifi {
                        Spacer()
                        Text(model.currentMicEndpoint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        CopyButton(text: model.currentMicEndpoint)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .panelFrame()
    }
}

private struct PhoneNetworkPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "手机网络给 Mac", state: model.phoneToMacState)
            RouteView(left: "Android", leftDetail: model.network.device, right: "Mac", rightDetail: model.network.defaultRoute, active: model.phoneToMacState.isOn)
            InfoRow("服务", model.network.service)
            InfoRow("IP", model.network.ip)
            InfoRow("网关", model.network.router)
        }
        .panelFrame()
    }
}

private struct MacRelayPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "Mac 网络给手机", state: model.macToPhoneState)
            RouteView(left: "Mac", leftDetail: "ADB relay", right: "Android", rightDetail: model.relaySocket, active: model.macToPhoneState.isOn)
            InfoRow("端口", "tcp:\(model.relayPort)")
            Text("gnirehtet 方向：电脑网络通过 ADB VPN 给手机。")
                .foregroundStyle(.secondary)
        }
        .panelFrame()
    }
}

private struct DevicePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "设备与 ADB", state: .running)
            InfoRow("ADB", model.adbPath)
            InfoRow("设备", model.deviceSummary)
            InfoRow("Reverse", model.reverseSummary)
        }
        .panelFrame()
    }
}

private struct LogPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("运行日志")
                .font(.title2.weight(.semibold))
            ScrollView {
                Text(model.logs.suffix(8).joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 180)
        .panelFrame()
    }
}

private struct PanelHeader: View {
    let title: String
    let state: AppModel.ModuleState

    var body: some View {
        HStack {
            Text(title)
                .font(.title2.weight(.semibold))
            Spacer()
            StatusCapsule(text: state.label, active: state.isOn)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.headline)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }
}

private struct RouteView: View {
    let left: String
    let leftDetail: String
    let right: String
    let rightDetail: String
    let active: Bool

    var body: some View {
        HStack(spacing: 14) {
            RouteNode(title: left, detail: leftDetail, active: active)
            Image(systemName: active ? "arrow.right.circle.fill" : "minus.circle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(active ? .cyan : .secondary)
            RouteNode(title: right, detail: rightDetail, active: active)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RouteNode: View {
    let title: String
    let detail: String
    let active: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(active ? Color.cyan.opacity(0.22) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WaveformView: View {
    let samples: [(Float, Float)]

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let maxHeight = size.height / 2

            guard !samples.isEmpty else {
                // 没有样本时画一条中线。
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: mid)); $0.addLine(to: CGPoint(x: size.width, y: mid)) },
                    with: .color(.secondary.opacity(0.45)),
                    lineWidth: 2
                )
                return
            }

            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: mid)); $0.addLine(to: CGPoint(x: size.width, y: mid)) },
                with: .color(.secondary.opacity(0.22)),
                lineWidth: 1
            )

            let step = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0
            let verticalScale = maxHeight * 0.92
            var path = Path()
            for (index, (_, maxVal)) in samples.enumerated() {
                let x = CGFloat(index) * step
                let value = min(max(CGFloat(maxVal.isFinite ? maxVal : 0), -1), 1)
                let point = CGPoint(x: x, y: mid - value * verticalScale)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            for (index, (minVal, _)) in samples.enumerated().reversed() {
                let x = CGFloat(index) * step
                let value = min(max(CGFloat(minVal.isFinite ? minVal : 0), -1), 1)
                let y = mid - value * verticalScale
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.closeSubpath()
            context.fill(path, with: .color(.cyan.opacity(0.85)))
        }
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // 离屏渲染合成，减少主线程绘制压力。
        .drawingGroup(opaque: false, colorMode: .linear)
    }
}

private func adapterLabel(_ adapter: NetworkAdapter, defaultRoute: String?) -> String {
    let suffix = adapter.name == defaultRoute ? " · 默认路由" : ""
    return "\(adapter.name) (\(adapter.ip))\(suffix)"
}

private struct CopyButton: View {
    let text: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("复制")
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private extension View {
    func glassPanel() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func panelFrame() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassPanel()
    }

    func statusCardFrame() -> some View {
        self
            .frame(minWidth: 0, maxWidth: .infinity)
    }
}
