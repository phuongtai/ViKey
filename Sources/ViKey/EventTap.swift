//  EventTap.swift
//  Chặn phím ở tầng phiên làm việc, đưa qua TelexEngine, rồi phát lại thành
//  Backspace + văn bản thật. Vì chữ được chèn thẳng vào ứng dụng chứ không phải
//  "marked text" của Input Method Kit nên KHÔNG có gạch chân ở bất kỳ app nào.

import AppKit
import ApplicationServices
import CoreGraphics
import VietEngine

/// Dấu nhận biết sự kiện do chính ta phát ra, để không xử lý lại chúng.
private let vikeyEventMarker: Int64 = 0x5649_4B45_5900

final class EventTap {

    private let engine = TelexEngine()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Gọi khi bật/tắt tiếng Việt bằng phím tắt, để cập nhật thanh menu.
    var onToggle: (() -> Void)?

    private static let backspaceKeyCode: CGKeyCode = 51
    private static let escapeKeyCode: CGKeyCode = 53
    private static let zKeyCode: CGKeyCode = 6

    init() { applyPreferences() }

    func applyPreferences() {
        engine.style = Preferences.shared.toneStyle
        engine.spellCheck = Preferences.shared.spellCheck
        engine.reset()
    }

    /// Xoá buffer khi ngữ cảnh soạn thảo có thể đã đổi (chuyển app, click chuột).
    func resetBuffer() { engine.reset() }

    // MARK: - Vòng đời

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(proxy: proxy, type: type, event: event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        runLoopSource = nil
        tap = nil
    }

    // MARK: - Xử lý sự kiện

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keep = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS tự ngắt tap nếu callback quá chậm; bật lại ngay.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            engine.reset()
            return keep

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // Con trỏ có thể nhảy đi chỗ khác -> buffer không còn khớp văn bản.
            engine.reset()
            return keep

        case .flagsChanged:
            return keep

        case .keyDown:
            break

        default:
            return keep
        }

        // Bỏ qua sự kiện do chính ta phát ra.
        if event.getIntegerValueField(.eventSourceUserData) == vikeyEventMarker { return keep }

        let flags = event.flags

        // Phím tắt bật/tắt tiếng Việt: ⌃⌥Z.
        if flags.contains(.maskControl), flags.contains(.maskAlternate),
           event.getIntegerValueField(.keyboardEventKeycode) == Int64(Self.zKeyCode) {
            Preferences.shared.vietnameseEnabled.toggle()
            engine.reset()
            DispatchQueue.main.async { [weak self] in self?.onToggle?() }
            return nil
        }

        guard Preferences.shared.vietnameseEnabled else { return keep }

        // Tổ hợp lệnh không phải là gõ văn bản -> ngắt từ.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            engine.reset()
            return keep
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == Self.backspaceKeyCode {
            let edit = engine.deleteBackward()
            return emit(edit.passthrough
                        ? Edit(backspaces: 1, insert: "", passthrough: false)
                        : edit,
                        proxy: proxy,
                        original: event)
        }

        // Lấy ký tự theo đúng bố cục bàn phím hiện hành. Mọi thứ không phải chữ
        // cái (dấu cách, dấu câu, mũi tên, phím chức năng) đều là ranh giới từ.
        guard let character = unicodeCharacter(of: event), character.isLetter else {
            engine.reset()
            return keep
        }

        let edit = engine.input(character, upper: character.isUppercase)
        if usesChromiumFallback, edit.backspaces > 0,
           replaceTextViaAccessibility(backspaces: edit.backspaces, insert: edit.insert) {
            // Thay thế qua Accessibility không đi qua luồng gõ bình thường của
            // Chromium, nên danh sách gợi ý (history/autocomplete) cũ vẫn có
            // thể mở. Escape chỉ đóng danh sách đó, không đổi văn bản vừa chèn.
            DispatchQueue.main.async { [weak self] in
                self?.postKey(Self.escapeKeyCode, proxy: proxy)
            }
            return nil
        }
        return emit(edit.passthrough
                    ? Edit(backspaces: 0, insert: String(character), passthrough: false)
                    : edit,
                    proxy: proxy,
                    original: event)
    }

    private func unicodeCharacter(of event: CGEvent) -> Character? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        guard text.count == 1 else { return nil }
        return text.first
    }

    private var usesChromiumFallback: Bool {
        switch NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
        case "com.google.Chrome", "com.microsoft.edgemac":
            return true
        default:
            return false
        }
    }

    private func replaceTextViaAccessibility(backspaces: Int, insert: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }
          let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)

        var selectionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectionValue) == .success,
              let selectionValue,
              CFGetTypeID(selectionValue) == AXValueGetTypeID() else { return false }
          let selection = unsafeBitCast(selectionValue, to: AXValue.self)

        var range = CFRange()
        guard AXValueGetValue(selection, .cfRange, &range), range.location >= backspaces else { return false }

        var replacementRange = CFRange(location: range.location - backspaces, length: backspaces)
        guard let selectedRange = AXValueCreate(.cfRange, &replacementRange),
              AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, selectedRange) == .success else {
            return false
        }
        return AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, insert as CFString) == .success
    }

    // MARK: - Phát sự kiện

    private func emit(_ edit: Edit, proxy: CGEventTapProxy, original: CGEvent) -> Unmanaged<CGEvent>? {
        if edit.passthrough { return Unmanaged.passUnretained(original) }

        // Chromium ignores a synthetic Backspace. For the common one-character
        // replacement (dd -> đ), turn the physical key-down itself into
        // Backspace, then insert the replacement after that event is handled.
        if edit.backspaces == 1, !edit.insert.isEmpty {
            let emptyText: [UniChar] = []
            original.setIntegerValueField(.keyboardEventKeycode, value: Int64(Self.backspaceKeyCode))
            original.keyboardSetUnicodeString(stringLength: 0, unicodeString: emptyText)
            original.flags = []
            DispatchQueue.main.async { [weak self] in
                self?.postText(edit.insert, proxy: proxy)
            }
            return Unmanaged.passUnretained(original)
        }

        for _ in 0..<edit.backspaces { postKey(Self.backspaceKeyCode, proxy: proxy) }
        if !edit.insert.isEmpty { postText(edit.insert, proxy: proxy) }
        return nil   // nuốt phím gốc
    }

    private func postKey(_ keyCode: CGKeyCode, proxy: CGEventTapProxy) {
        for isDown in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            e.flags = []
            e.setIntegerValueField(.eventSourceUserData, value: vikeyEventMarker)
            // Chromium ignores Backspace posted through the current session-tap
            // proxy. Posting at HID level makes the replacement delete apply.
            e.post(tap: .cghidEventTap)
        }
    }

    private func postText(_ text: String, proxy: CGEventTapProxy) {
        if Preferences.shared.sendPerCharacter {
            for character in text { postUnicode(String(character), proxy: proxy) }
        } else {
            postUnicode(text, proxy: proxy)
        }
    }

    private func postUnicode(_ text: String, proxy: CGEventTapProxy) {
        let utf16 = Array(text.utf16)
        for isDown in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
            e.flags = []
            // Chromium inserts the Unicode payload on both events when it is
            // attached to key-up as well. Text belongs on key-down only.
            if isDown {
                e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            }
            e.setIntegerValueField(.eventSourceUserData, value: vikeyEventMarker)
            e.post(tap: .cghidEventTap)
        }
    }
}
