//  Preferences.swift

import Foundation
import VietEngine

final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let vietnameseEnabled = "vietnameseEnabled"
        static let toneStyle = "toneStyle"
        static let spellCheck = "spellCheck"
        static let sendPerCharacter = "sendPerCharacter"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.vietnameseEnabled: true,
            Key.toneStyle: ToneStyle.modern.rawValue,
            Key.spellCheck: true,
            Key.sendPerCharacter: true,
        ])
    }

    var vietnameseEnabled: Bool {
        get { defaults.bool(forKey: Key.vietnameseEnabled) }
        set { defaults.set(newValue, forKey: Key.vietnameseEnabled) }
    }

    var toneStyle: ToneStyle {
        get { ToneStyle(rawValue: defaults.string(forKey: Key.toneStyle) ?? "") ?? .modern }
        set { defaults.set(newValue.rawValue, forKey: Key.toneStyle) }
    }

    var spellCheck: Bool {
        get { defaults.bool(forKey: Key.spellCheck) }
        set { defaults.set(newValue, forKey: Key.spellCheck) }
    }

    /// Gửi từng ký tự một thay vì cả chuỗi trong một sự kiện. Chậm hơn chút
    /// nhưng tương thích rộng hơn (Electron, Java, một số terminal).
    var sendPerCharacter: Bool {
        get { defaults.bool(forKey: Key.sendPerCharacter) }
        set { defaults.set(newValue, forKey: Key.sendPerCharacter) }
    }
}
