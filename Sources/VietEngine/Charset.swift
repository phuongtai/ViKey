//  Charset.swift
//  Bảng ký tự tiếng Việt: dấu phụ (mark) trên nguyên âm + thanh điệu (tone).
//  Thuần Swift, không phụ thuộc AppKit — để unit-test được toàn bộ.

import Foundation

/// Thanh điệu. Thứ tự phải khớp với cột trong `toneTable`.
public enum Tone: Int, Sendable, CaseIterable {
    case none = 0   // ngang
    case acute      // sắc
    case grave      // huyền
    case hook       // hỏi
    case tilde      // ngã
    case dot        // nặng
}

/// Dấu phụ gắn liền với chữ cái (không phải thanh điệu).
public enum Mark: Int, Sendable {
    case none = 0
    case hat        // â ê ô
    case breve      // ă
    case horn       // ơ ư
    case stroke     // đ
}

public enum Charset {

    /// base + mark -> chữ cái có dấu phụ (chưa có thanh).
    /// Chỉ liệt kê các tổ hợp hợp lệ trong tiếng Việt.
    static let markTable: [Character: [Mark: Character]] = [
        "a": [.hat: "â", .breve: "ă"],
        "e": [.hat: "ê"],
        "o": [.hat: "ô", .horn: "ơ"],
        "u": [.horn: "ư"],
        "d": [.stroke: "đ"],
    ]

    /// Chữ cái (đã có dấu phụ) -> 6 biến thể thanh điệu, theo thứ tự `Tone`.
    static let toneTable: [Character: [Character]] = [
        "a": ["a", "á", "à", "ả", "ã", "ạ"],
        "ă": ["ă", "ắ", "ằ", "ẳ", "ẵ", "ặ"],
        "â": ["â", "ấ", "ầ", "ẩ", "ẫ", "ậ"],
        "e": ["e", "é", "è", "ẻ", "ẽ", "ẹ"],
        "ê": ["ê", "ế", "ề", "ể", "ễ", "ệ"],
        "i": ["i", "í", "ì", "ỉ", "ĩ", "ị"],
        "o": ["o", "ó", "ò", "ỏ", "õ", "ọ"],
        "ô": ["ô", "ố", "ồ", "ổ", "ỗ", "ộ"],
        "ơ": ["ơ", "ớ", "ờ", "ở", "ỡ", "ợ"],
        "u": ["u", "ú", "ù", "ủ", "ũ", "ụ"],
        "ư": ["ư", "ứ", "ừ", "ử", "ữ", "ự"],
        "y": ["y", "ý", "ỳ", "ỷ", "ỹ", "ỵ"],
    ]

    /// Chữ cái có dấu phụ -> chữ cái gốc không dấu phụ. Dùng cho so khớp "nới lỏng".
    static let stripTable: [Character: Character] = [
        "â": "a", "ă": "a", "ê": "e", "ô": "o", "ơ": "o", "ư": "u", "đ": "d",
    ]

    /// Nguyên âm (đã tính cả biến thể có dấu phụ).
    static let vowels: Set<Character> = ["a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y"]


    public static func isVowel(_ c: Character) -> Bool { vowels.contains(c) }

    /// Ghép base + mark. Trả về nil nếu tổ hợp không hợp lệ (vd. "b" + .hat).
    public static func compose(_ base: Character, _ mark: Mark) -> Character? {
        if mark == .none { return base }
        return markTable[base]?[mark]
    }

    /// Đặt thanh điệu lên một chữ cái. Trả về chính nó nếu chữ đó không nhận thanh.
    public static func applyTone(_ letter: Character, _ tone: Tone) -> Character {
        guard let row = toneTable[letter] else { return letter }
        return row[tone.rawValue]
    }

    /// Bỏ dấu phụ: ế -> e. (Không dùng cho chữ đã có thanh.)
    public static func stripMark(_ c: Character) -> Character { stripTable[c] ?? c }

    /// Bỏ dấu phụ cho cả chuỗi.
    public static func stripMarks(_ s: String) -> String { String(s.map(stripMark)) }
}
