import AppKit
import ApplicationServices

private enum CopyMode: String {
    case safe
    case normal

    var menuTitle: String {
        switch self {
        case .safe:
            return "モード: Option + 右ダブルクリック"
        case .normal:
            return "モード: 右ダブルクリック"
        }
    }
}

private enum TrackingState {
    case idle
    case mouseDown
    case dragging
    case copyArmed
    case copied
}

@MainActor
private final class QuickCopyController: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaults = UserDefaults.standard
    private var eventMonitor: Any?
    private var armTimer: Timer?
    private var feedbackTimer: Timer?
    private var copiedToastWindow: NSPanel?
    private var mouseDownLocation: NSPoint?
    private var state: TrackingState = .idle

    private let dragThreshold: CGFloat = 8
    private let copyArmDuration: TimeInterval = 2

    private var isEnabled: Bool {
        get {
            if defaults.object(forKey: "isEnabled") == nil {
                return true
            }
            return defaults.bool(forKey: "isEnabled")
        }
        set {
            defaults.set(newValue, forKey: "isEnabled")
            if !newValue {
                resetState()
            }
            updateStatusIcon()
            rebuildMenu()
        }
    }

    private var copyMode: CopyMode {
        get {
            CopyMode(rawValue: defaults.string(forKey: "copyMode") ?? "") ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: "copyMode")
            rebuildMenu()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = NSStatusItem.squareLength
        updateStatusIcon()
        rebuildMenu()
        installEventMonitor()
        if !hasAccessibilityPermission(prompt: true) {
            showPermissionDialog()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        armTimer?.invalidate()
        feedbackTimer?.invalidate()
        copiedToastWindow?.close()
    }

    private func installEventMonitor() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled, hasAccessibilityPermission(prompt: false) else {
            return
        }

        switch event.type {
        case .leftMouseDown:
            handleMouseDown(event)
        case .rightMouseDown:
            handleTriggerMouseDown(event)
        case .leftMouseDragged:
            handleMouseDragged(event)
        case .leftMouseUp:
            handleMouseUp(event)
        default:
            break
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        if case .copyArmed = state {
            return
        }

        mouseDownLocation = NSEvent.mouseLocation
        state = .mouseDown
        updateStatusIcon()
    }

    private func handleTriggerMouseDown(_ event: NSEvent) {
        guard case .copyArmed = state, event.clickCount == 2 else {
            return
        }

        performCopyIfModeMatches(event)
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard let start = mouseDownLocation else {
            return
        }

        let current = NSEvent.mouseLocation
        let distance = hypot(current.x - start.x, current.y - start.y)
        if distance >= dragThreshold {
            state = .dragging
            updateStatusIcon()
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard case .dragging = state else {
            if case .mouseDown = state {
                resetState()
            }
            return
        }

        armCopyWindow()
    }

    private func armCopyWindow() {
        state = .copyArmed
        mouseDownLocation = nil
        armTimer?.invalidate()
        armTimer = Timer.scheduledTimer(withTimeInterval: copyArmDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resetState()
            }
        }
        updateStatusIcon()
    }

    private func performCopyIfModeMatches(_ event: NSEvent) {
        if copyMode == .safe && !event.modifierFlags.contains(.option) {
            return
        }

        armTimer?.invalidate()
        state = .copied
        sendCommandC()
        showCopiedFeedback()
    }

    private func sendCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func showCopiedFeedback() {
        setStatusSymbol(name: "checkmark.circle.fill", accessibilityDescription: "コピーしました")
        showCopiedToast()
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideCopiedToast()
                self?.resetState()
            }
        }
    }

    private func showCopiedToast() {
        hideCopiedToast()

        let toastSize = NSSize(width: 106, height: 34)
        var origin = NSEvent.mouseLocation
        origin.x -= toastSize.width + 18
        origin.y += 14

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            let visibleFrame = screen.visibleFrame
            if origin.x < visibleFrame.minX + 8 {
                origin.x = NSEvent.mouseLocation.x + 18
            }
            if origin.y > visibleFrame.maxY - toastSize.height - 8 {
                origin.y = NSEvent.mouseLocation.y - toastSize.height - 14
            }
            origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - toastSize.width - 8)
            origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - toastSize.height - 8)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: toastSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let label = NSTextField(labelWithString: "Copied")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "コピーしました")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.31, blue: 0.62, alpha: 0.96).cgColor
        container.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.22).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = 9
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        panel.contentView = container
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15)
        ])

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        copiedToastWindow = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hideCopiedToast() {
        guard let panel = copiedToastWindow else {
            return
        }

        copiedToastWindow = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.close()
        }
    }

    private func resetState() {
        state = .idle
        mouseDownLocation = nil
        armTimer?.invalidate()
        armTimer = nil
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.imagePosition = .imageOnly

        if !isEnabled {
            button.contentTintColor = .disabledControlTextColor
            setStatusSymbol(name: "doc.on.doc", accessibilityDescription: "QuickCopy オフ")
            return
        }

        button.contentTintColor = nil
        switch state {
        case .copyArmed:
            setStatusSymbol(name: "bolt.circle.fill", accessibilityDescription: "コピー待機中")
        case .copied:
            setStatusSymbol(name: "checkmark.circle.fill", accessibilityDescription: "コピーしました")
        default:
            setStatusSymbol(name: "doc.on.doc", accessibilityDescription: "QuickCopy オン")
        }
    }

    private func setStatusSymbol(name: String, accessibilityDescription: String) {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        button.image = image
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: isEnabled ? "QuickCopy: オン" : "QuickCopy: オフ",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)

        let modeItem = NSMenuItem(title: copyMode.menuTitle, action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        let safeItem = NSMenuItem(
            title: "安全モード: ドラッグ + Option + 右ダブルクリック",
            action: #selector(setSafeMode),
            keyEquivalent: ""
        )
        safeItem.target = self
        safeItem.state = copyMode == .safe ? .on : .off
        modeMenu.addItem(safeItem)

        let normalItem = NSMenuItem(
            title: "通常モード: ドラッグ + 右ダブルクリック",
            action: #selector(setNormalMode),
            keyEquivalent: ""
        )
        normalItem.target = self
        normalItem.state = copyMode == .normal ? .on : .off
        modeMenu.addItem(normalItem)
        menu.setSubmenu(modeMenu, for: modeItem)
        menu.addItem(modeItem)

        let permissionTitle = hasAccessibilityPermission(prompt: false) ? "権限: OK" : "権限: 必要"
        let permissionItem = NSMenuItem(
            title: permissionTitle,
            action: #selector(checkPermission),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let settingsItem = NSMenuItem(
            title: "システム設定を開く",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "QuickCopyを終了",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func showPermissionDialog() {
        let alert = NSAlert()
        alert.messageText = "QuickCopyにアクセシビリティ権限が必要です"
        alert.informativeText = "QuickCopyがマウス操作を検知し、コピー操作を送信するにはアクセシビリティ権限が必要です。\n\nシステム設定 > プライバシーとセキュリティ > アクセシビリティ でQuickCopyを許可してください。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "再チェック")
        alert.addButton(withTitle: "あとで")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openAccessibilitySettings()
        case .alertSecondButtonReturn:
            rebuildMenu()
            if !hasAccessibilityPermission(prompt: false) {
                showPermissionDialog()
            }
        default:
            break
        }
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }

    @objc private func setSafeMode() {
        copyMode = .safe
    }

    @objc private func setNormalMode() {
        copyMode = .normal
    }

    @objc private func checkPermission() {
        if hasAccessibilityPermission(prompt: true) {
            rebuildMenu()
        } else {
            showPermissionDialog()
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
private enum QuickCopyMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = QuickCopyController()
        app.delegate = delegate
        app.run()
    }
}
