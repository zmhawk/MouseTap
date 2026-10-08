import SwiftUI

struct ContentView: View {
    private let monitor = MouseEventMonitor.shared
    @State private var bindings = BindingStore.load()
    @State private var scrollSettings = ScrollSettings.load()
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    @State private var status = "正在启动监听器…"
    @State private var latestInput: String?
    @State private var isAddingBinding = false
    @State private var isLearningInput = false
    @State private var pendingInput: MouseInput?
    @State private var pendingShortcut: ShortcutBinding?
    @State private var isCapturingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()

            HStack {
                Text("按键绑定")
                    .font(.headline)
                Spacer()
                Button {
                    beginAddingBinding()
                } label: {
                    Label("添加绑定", systemImage: "plus")
                }
                .disabled(isAddingBinding)
            }

            if isAddingBinding {
                addBindingForm
            }

            if bindings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "computermouse")
                        .font(.system(size: 28))
                    Text("还没有绑定")
                        .font(.headline)
                    Text("添加一个鼠标输入，再录制它要触发的快捷键。")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 0) {
                    ForEach(bindings.keys.sorted(), id: \.self) { inputID in
                        if let shortcut = bindings[inputID] {
                            bindingRow(inputID: inputID, shortcut: shortcut)
                            if inputID != bindings.keys.sorted().last {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.quaternary, lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("滚轮方向").font(.headline)
                HStack(spacing: 24) {
                    Toggle("反转上下滚动", isOn: $scrollSettings.reverseVertical)
                    Toggle("反转左右滚动", isOn: $scrollSettings.reverseHorizontal)
                }
                .toggleStyle(.checkbox)
                Text("相对于系统方向反转；横向拨轮的快捷键绑定保持不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Divider()
            HStack {
                Toggle("开机自启", isOn: Binding(
                    get: { launchAtLogin.enabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("退出 Mouse Kit") { NSApp.terminate(nil) }
            }
            Text("关闭窗口后继续在后台运行；再次打开 App 可显示此窗口。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if launchAtLogin.requiresApproval {
                HStack {
                    Text("请在系统设置中允许开机自启。")
                    Button("打开登录项设置") { launchAtLogin.openSettings() }
                }
                .font(.caption)
            }
            if let error = launchAtLogin.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            HStack(spacing: 6) {
                Image(systemName: "waveform.path")
                    .foregroundStyle(.secondary)
                Text(latestInput.map { "最近识别：\($0)" } ?? "等待鼠标输入")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("左右键保持默认")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .padding(22)
        .onAppear(perform: startMonitor)
        .onChange(of: scrollSettings) { settings in
            settings.save()
            monitor.setScrollSettings(settings)
        }
        .onDisappear(perform: detachViewCallbacks)
        .onReceive(NotificationCenter.default.publisher(for: .mouseKitWindowHidden)) { _ in
            cancelAddingBinding()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mouse Kit")
                    .font(.title2.weight(.semibold))
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(status.hasPrefix("正在监听") ? .secondary : .orange)
            }
            Spacer()
            if status.hasPrefix("正在监听") {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                    .accessibilityLabel("正在监听")
            }
        }
    }

    private var addBindingForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("触发输入", systemImage: "computermouse")
                    .frame(width: 110, alignment: .leading)
                if let pendingInput {
                    Text(pendingInput.title)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                } else {
                    Button(isLearningInput ? "请按鼠标键…" : "识别鼠标键") {
                        startLearningInput()
                    }
                    .disabled(isLearningInput)
                }
                Spacer()
            }

            HStack {
                Label("执行快捷键", systemImage: "command")
                    .frame(width: 110, alignment: .leading)
                ShortcutRecorder(
                    shortcut: $pendingShortcut,
                    isCapturing: $isCapturingShortcut,
                    onBeginCapture: beginShortcutCapture
                )
                    .frame(width: 190, height: 34)
                Spacer()
            }

            HStack {
                Text("支持中键、额外按键和横向拨轮。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", role: .cancel) {
                    cancelAddingBinding()
                }
                Button("保存") {
                    saveBinding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingInput == nil || pendingShortcut == nil)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bindingRow(inputID: String, shortcut: ShortcutBinding) -> some View {
        HStack(spacing: 12) {
            Image(systemName: inputID.hasPrefix("scroll.") ? "arrow.left.arrow.right" : "computermouse")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(MouseInput(id: inputID).title)
            Spacer()
            Text(shortcut.displayName)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Button(role: .destructive) {
                removeBinding(inputID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除绑定")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func startMonitor() {
        monitor.onInputDetected = { input in
            latestInput = input.title
            guard isLearningInput else { return }
            pendingInput = input
            isLearningInput = false
            monitor.setLearningMode(false)
        }
        monitor.onStatusChanged = { status = $0 }
        monitor.setBindings(bindings)
        monitor.setScrollSettings(scrollSettings)
        monitor.start()
    }

    private func detachViewCallbacks() {
        monitor.setLearningMode(false)
        monitor.cancelShortcutCapture()
        monitor.onInputDetected = nil
        monitor.onStatusChanged = nil
    }

    private func beginAddingBinding() {
        isAddingBinding = true
        pendingInput = nil
        pendingShortcut = nil
    }

    private func startLearningInput() {
        pendingInput = nil
        isLearningInput = true
        monitor.setLearningMode(true)
        monitor.start()
    }

    private func beginShortcutCapture() {
        monitor.beginShortcutCapture { shortcut in
            isCapturingShortcut = false
            if let shortcut { pendingShortcut = shortcut }
        }
    }

    private func cancelAddingBinding() {
        isLearningInput = false
        isCapturingShortcut = false
        monitor.cancelShortcutCapture()
        monitor.setLearningMode(false)
        isAddingBinding = false
        pendingInput = nil
        pendingShortcut = nil
    }

    private func saveBinding() {
        guard let pendingInput, let pendingShortcut else { return }
        bindings[pendingInput.id] = pendingShortcut
        persistBindings()
        monitor.setBindings(bindings)
        cancelAddingBinding()
    }

    private func removeBinding(_ inputID: String) {
        bindings.removeValue(forKey: inputID)
        persistBindings()
        monitor.setBindings(bindings)
    }

    private func persistBindings() {
        BindingStore.save(bindings)
    }

}
