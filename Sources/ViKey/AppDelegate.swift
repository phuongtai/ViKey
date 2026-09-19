//  AppDelegate.swift
//  Ứng dụng nền, chỉ có biểu tượng trên thanh menu (LSUIElement).

import AppKit
import ApplicationServices
import VietEngine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let tap = EventTap()
    private var statusItem: NSStatusItem!
    private let prefs = Preferences.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        tap.onToggle = { [weak self] in self?.refreshStatusItem() }

        // Chuyển app hoặc đổi không gian làm việc -> văn bản đích đã khác.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(contextChanged),
                              name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(contextChanged),
                              name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        guard requestAccessibilityPermission() else { return }
        startTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.stop()
    }

    @objc private func contextChanged() { tap.resetBuffer() }

    // MARK: - Quyền trợ năng

    private func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return true }

        // Hệ thống đã hiện hộp thoại; chờ người dùng cấp quyền rồi tự khởi động.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.startTap()
            self?.refreshStatusItem()
        }
        refreshStatusItem()
        return false
    }

    private func startTap() {
        guard tap.start() else {
            let alert = NSAlert()
            alert.messageText = "Không tạo được bộ chặn phím"
            alert.informativeText = """
                ViKey cần quyền Trợ năng (Accessibility) để hoạt động.
                Mở Cài đặt Hệ thống › Quyền riêng tư & Bảo mật › Trợ năng,
                bật ViKey, rồi mở lại ứng dụng.
                """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Mở Cài đặt")
            alert.addButton(withTitle: "Đóng")
            if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }
            return
        }
        refreshStatusItem()
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Thanh menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        let trusted = AXIsProcessTrusted()
        statusItem.button?.title = !trusted ? "!" : (prefs.vietnameseEnabled ? "VI" : "EN")
        statusItem.button?.toolTip = trusted
            ? "ViKey — \(prefs.vietnameseEnabled ? "tiếng Việt" : "tiếng Anh")"
            : "ViKey — chưa được cấp quyền Trợ năng"
        statusItem.menu = buildMenu(trusted: trusted)
    }

    private func buildMenu(trusted: Bool) -> NSMenu {
        let menu = NSMenu()

        if !trusted {
            menu.addItem(withTitle: "Chưa có quyền Trợ năng", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Mở Cài đặt Hệ thống…",
                         action: #selector(openSettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }

        let toggle = menu.addItem(withTitle: prefs.vietnameseEnabled ? "Tiếng Việt" : "Tiếng Anh",
                                  action: #selector(toggleVietnamese), keyEquivalent: "z")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.state = prefs.vietnameseEnabled ? .on : .off
        toggle.target = self

        menu.addItem(.separator())

        let styleItem = menu.addItem(withTitle: "Kiểu bỏ dấu", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for (title, style) in [("Kiểu mới  (hoà, thuý)", ToneStyle.modern),
                               ("Kiểu cũ  (hòa, thúy)", ToneStyle.classic)] {
            let item = styleMenu.addItem(withTitle: title, action: #selector(setToneStyle(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = prefs.toneStyle == style ? .on : .off
            item.target = self
        }
        styleItem.submenu = styleMenu

        let spell = menu.addItem(withTitle: "Kiểm tra chính tả",
                                 action: #selector(toggleSpellCheck), keyEquivalent: "")
        spell.state = prefs.spellCheck ? .on : .off
        spell.target = self
        spell.toolTip = "Không bỏ dấu cho tổ hợp không phải tiếng Việt, và trả lại phím gốc."

        let perChar = menu.addItem(withTitle: "Chế độ tương thích",
                                   action: #selector(toggleCompatibility), keyEquivalent: "")
        perChar.state = prefs.sendPerCharacter ? .on : .off
        perChar.target = self
        perChar.toolTip = "Gửi từng ký tự một. Bật nếu gõ bị lỗi trong Electron, Java hoặc terminal."

        menu.addItem(.separator())
        menu.addItem(withTitle: "Thoát ViKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // MARK: - Hành động

    @objc private func openSettings() { openAccessibilitySettings() }

    @objc private func toggleVietnamese() {
        prefs.vietnameseEnabled.toggle()
        tap.resetBuffer()
        refreshStatusItem()
    }

    @objc private func setToneStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = ToneStyle(rawValue: raw) else { return }
        prefs.toneStyle = style
        tap.applyPreferences()
        refreshStatusItem()
    }

    @objc private func toggleSpellCheck() {
        prefs.spellCheck.toggle()
        tap.applyPreferences()
        refreshStatusItem()
    }

    @objc private func toggleCompatibility() {
        prefs.sendPerCharacter.toggle()
        refreshStatusItem()
    }
}
