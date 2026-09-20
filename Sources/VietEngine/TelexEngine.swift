//  TelexEngine.swift
//  Bộ gõ Telex. Giữ trạng thái của TỪ đang gõ và trả về "phép sửa" cần áp dụng
//  lên văn bản đã hiển thị (xoá n ký tự + chèn chuỗi mới).
//
//  Hai quyết định thiết kế quan trọng:
//
//  1. Trạng thái lưu ở dạng ĐÃ XỬ LÝ (từng chữ cái kèm dấu phụ của nó) chứ
//     không phải chuỗi phím thô. Nhờ vậy Backspace luôn đồng bộ chính xác.
//
//  2. Mỗi đơn vị vẫn nhớ chuỗi phím gốc đã sinh ra nó (`raw`). Khi phát hiện từ
//     này không phải tiếng Việt, ta dựng lại nguyên văn những gì người dùng đã
//     gõ. Nếu không có bước này, "merge" sẽ ra "mege" — phím r bị ăn mất làm
//     dấu hỏi rồi biến mất khi dấu hỏi bị từ chối.

import Foundation

/// Phép sửa cần áp dụng lên văn bản đang hiển thị.
public struct Edit: Equatable, Sendable {
    /// Số lần gửi phím Backspace.
    public var backspaces: Int
    /// Chuỗi cần chèn sau khi xoá.
    public var insert: String
    /// Nếu true: không can thiệp, để hệ thống xử lý phím gốc như bình thường.
    public var passthrough: Bool

    public static let pass = Edit(backspaces: 0, insert: "", passthrough: true)

    public init(backspaces: Int, insert: String, passthrough: Bool) {
        self.backspaces = backspaces
        self.insert = insert
        self.passthrough = passthrough
    }

    /// Không phải làm gì cả, kể cả phím gốc cũng bị nuốt.
    public var isNoop: Bool { !passthrough && backspaces == 0 && insert.isEmpty }
}

public final class TelexEngine {

    // MARK: - Cấu hình

    public var style: ToneStyle = .modern
    /// Bật kiểm tra chính tả: từ chối bỏ dấu cho tổ hợp không phải tiếng Việt
    /// và hoàn nguyên phím gốc khi phát hiện.
    public var spellCheck: Bool = true
    /// Quá dài thì ngừng xử lý, tránh trường hợp bệnh lý.
    public let maxWordLength = 32

    // MARK: - Trạng thái từ đang gõ

    private struct Unit {
        var base: Character        // chữ cái gốc, chữ thường, chưa có dấu phụ
        var mark: Mark = .none
        var markKey: Character?    // phím đã tạo ra dấu phụ (gõ lại thì huỷ)
        var upper = false
        var raw: String            // phím gốc sinh ra đơn vị này, giữ nguyên hoa/thường
    }

    private var units: [Unit] = []
    private var tone: Tone = .none
    private var toneKey: Character?
    /// Phím thanh người dùng đã gõ, giữ nguyên hoa/thường; có thể tích luỹ khi
    /// đổi thanh nhiều lần ("asf" -> "sf").
    private var toneRaw: String?
    /// Vị trí (theo số đơn vị) mà phím thanh đã được gõ, dùng khi hoàn nguyên.
    private var toneAnchor = 0
    /// Đã xác định đây không phải từ tiếng Việt: ngừng mọi biến đổi tới hết từ.
    private var blocked = false

    public init() {}

    // MARK: - Bảng phím Telex

    private static let toneKeys: [Character: Tone] = [
        "s": .acute, "f": .grave, "r": .hook, "x": .tilde, "j": .dot,
    ]
    private static let markKeys: Set<Character> = ["a", "e", "o", "w", "d"]

    // MARK: - Truy vấn

    /// Văn bản mà từ đang gõ đang hiển thị trên màn hình.
    public var currentText: String { render() }
    public var isEmpty: Bool { units.isEmpty }

    public func reset() {
        units.removeAll(keepingCapacity: true)
        tone = .none
        toneKey = nil
        toneRaw = nil
        toneAnchor = 0
        blocked = false
    }

    // MARK: - Đầu vào

    /// Nhận một chữ cái. `upper` là true nếu người dùng gõ chữ hoa.
    public func input(_ character: Character, upper: Bool) -> Edit {
        guard character.isLetter else { reset(); return .pass }
        let key = Character(character.lowercased())
        let before = render()

        if blocked || units.count >= maxWordLength {
            appendLiteral(character, upper: upper)
            return diff(from: before, typed: character)
        }
        if let t = Self.toneKeys[key], applyToneKey(t, key: key, typed: character, upper: upper) {
            return diff(from: before, typed: character)
        }
        if key == "z", removeTone() {
            return diff(from: before, typed: character)
        }
        if Self.markKeys.contains(key), applyMarkKey(key, typed: character, upper: upper) {
            return diff(from: before, typed: character)
        }
        appendLiteral(character, upper: upper)
        return diff(from: before, typed: character)
    }

    /// Nhận phím Backspace: bỏ một chữ cái khỏi từ đang gõ.
    public func deleteBackward() -> Edit {
        guard !units.isEmpty else { return .pass }
        let before = render()
        units.removeLast()
        toneAnchor = min(toneAnchor, units.count)
        if units.isEmpty {
            reset()
        } else {
            if tone != .none, tonePosition() == nil { tone = .none; toneKey = nil; toneRaw = nil }
            blocked = spellCheck && !Syllable.isPlausiblePrefix(letters())
        }
        let after = render()
        // Trường hợp thường gặp: chỉ mất đúng ký tự cuối -> để hệ thống tự xoá.
        if after == String(before.dropLast()) { return .pass }
        return rawDiff(before, after)
    }

    // MARK: - Thanh điệu

    private func applyToneKey(_ t: Tone, key: Character, typed: Character, upper: Bool) -> Bool {
        // Gõ lại đúng phím thanh đang dùng -> huỷ thanh và nhả phím đã tạo thanh.
        if tone != .none, toneKey == key {
            let carried = toneRaw ?? ""
            tone = .none; toneKey = nil; toneRaw = nil
            for c in carried {
                appendLiteral(c, upper: c.isUppercase, escaping: true)
            }
            return true
        }
        guard tonePosition() != nil else { return false }
        if toneRaw == nil { toneAnchor = units.count }
        tone = t
        toneKey = key
        toneRaw = (toneRaw ?? "") + String(typed)
        return true
    }

    private func removeTone() -> Bool {
        guard tone != .none else { return false }
        tone = .none
        toneKey = nil
        toneRaw = nil
        return true
    }

    /// Vị trí đặt thanh trong `units`, hoặc nil nếu không đặt được.
    private func tonePosition() -> Int? {
        let ls = letters()
        if let p = Syllable.tonePosition(ls, style: style) { return p }
        guard !spellCheck else { return nil }
        return ls.lastIndex(where: Charset.isVowel)
    }

    // MARK: - Dấu phụ

    private func applyMarkKey(_ key: Character, typed: Character, upper: Bool) -> Bool {
        switch key {
        case "a", "e", "o": return applyDoubling(key, typed: typed, upper: upper)
        case "d": return applyStroke(typed: typed, upper: upper)
        case "w": return applyHornOrBreve(typed: typed, upper: upper)
        default: return false
        }
    }

    /// aa -> â, ee -> ê, oo -> ô. Gõ lần ba thì trả lại hai chữ cái gốc.
    private func applyDoubling(_ key: Character, typed: Character, upper: Bool) -> Bool {
        guard let last = units.last, last.base == key else { return false }
        let index = units.count - 1

        if last.mark == .hat, last.markKey == key {
            let dropped = units[index].raw.removeLast()
            units[index].mark = .none
            units[index].markKey = nil
            appendLiteral(typed, upper: upper, rawPrefix: String(dropped), escaping: true)
            return true
        }
        guard last.mark == .none else { return false }

        let snapshot = units
        units[index].mark = .hat
        units[index].markKey = key
        units[index].raw.append(typed)
        if !isStillPlausible() { units = snapshot; return false }
        return true
    }

    /// dd -> đ; cũng hỗ trợ did -> đi. Gõ lại phím d thì hoàn nguyên chữ gốc.
    private func applyStroke(typed: Character, upper: Bool) -> Bool {
        let index: Int
        if let last = units.last, last.base == "d" {
            index = units.count - 1
        } else if units.count > 1, units[0].base == "d",
              units.indices.dropFirst().allSatisfy({ Charset.isVowel(letterAt($0)) }) {
            index = 0
        } else {
            return false
        }

        if units[index].mark == .stroke, units[index].markKey == "d" {
            let dropped = units[index].raw.removeLast()
            units[index].mark = .none
            units[index].markKey = nil
            appendLiteral(typed, upper: upper, rawPrefix: String(dropped), escaping: true)
            return true
        }
        guard units[index].mark == .none else { return false }
        units[index].mark = .stroke
        units[index].markKey = "d"
        units[index].raw.append(typed)
        return true
    }

    /// w -> ă / ơ / ư. Trên cụm "uo" đặt móc cho cả hai ("ươ"); trên "ua"
    /// thì đặt móc lên u ("ưa").
    /// Chỉ khi không còn nguyên âm nào nhận thêm dấu thì w mới huỷ dấu cũ
    /// ("aww" -> "aw"); nếu huỷ sớm thì "nguwowif" sẽ mất chữ ư.
    private func applyHornOrBreve(typed: Character, upper: Bool) -> Bool {
        let cluster = lastVowelCluster()

        // Sau một âm đầu hợp lệ, w chính là "ư" ("tw" -> "tư"). Một w đứng
        // riêng phải được giữ nguyên để người dùng vẫn gõ được ký tự Latin này.
        if cluster.isEmpty, !units.isEmpty, Syllable.isPlausiblePrefix(letters()),
           !units.contains(where: { $0.markKey == "w" }) {
            units.append(Unit(base: "u", mark: .horn, markKey: "w", upper: upper, raw: String(typed)))
            return true
        }

        var targets: [Int] = []
        // Cụm "uo" liền nhau -> "ươ", miễn là còn ít nhất một chữ chưa có dấu.
        for i in cluster.dropLast() {
            let j = i + 1
            guard cluster.contains(j) else { continue }
            if units[i].base == "u", units[j].base == "o",
               units[i].mark == .none || units[j].mark == .none {
                targets = [i, j]
                break
            }
            if units[i].base == "u", units[j].base == "a", units[i].mark == .none {
                targets = [i]
                break
            }
        }
        if targets.isEmpty, let i = cluster.last(where: {
            units[$0].mark == .none && ["a", "o", "u"].contains(units[$0].base)
        }) {
            targets = [i]
        }

        // Không còn gì để thêm dấu -> huỷ các dấu do chính phím w tạo ra.
        if targets.isEmpty {
            let madeByW = units.indices.filter { units[$0].markKey == "w" }
            guard !madeByW.isEmpty else { return false }
            var dropped = ""
            for i in madeByW {
                if let last = units[i].raw.last, last.lowercased() == "w" {
                    dropped = String(units[i].raw.removeLast())
                }
                units[i].mark = .none
                units[i].markKey = nil
            }
            appendLiteral(typed, upper: upper, rawPrefix: dropped, escaping: true)
            return true
        }

        let snapshot = units
        for i in targets {
            units[i].mark = units[i].base == "a" ? .breve : .horn
            units[i].markKey = "w"
        }
        units[targets[targets.count - 1]].raw.append(typed)
        if !isStillPlausible() { units = snapshot; return false }
        return true
    }

    /// Chỉ số các đơn vị thuộc dãy nguyên âm liền nhau ở cuối từ.
    private func lastVowelCluster() -> [Int] {
        var end = units.count - 1
        while end >= 0, !Charset.isVowel(letterAt(end)) { end -= 1 }
        guard end >= 0 else { return [] }
        var start = end
        while start - 1 >= 0, Charset.isVowel(letterAt(start - 1)) { start -= 1 }
        return Array(start...end)
    }

    // MARK: - Chèn thẳng & kiểm tra chính tả

    /// `escaping` = true khi chữ cái này đến từ thao tác HUỶ dấu ("aaa" -> "aa").
    /// Đó là ý muốn rõ ràng của người dùng, không phải lỗi chính tả, nên không
    /// được hoàn nguyên phím gốc — nếu không "aaa" sẽ thành "aaa" thay vì "aa".
    private func appendLiteral(_ typed: Character, upper: Bool,
                               rawPrefix: String = "", escaping: Bool = false) {
        units.append(Unit(base: Character(typed.lowercased()),
                          upper: upper,
                          raw: rawPrefix + String(typed)))
        if escaping {
            if spellCheck, !Syllable.isPlausiblePrefix(letters()) { blocked = true }
        } else {
            enforceSpelling()
        }
    }

    private func isStillPlausible() -> Bool {
        guard spellCheck else { return true }
        return Syllable.isPlausiblePrefix(letters())
    }

    /// Phát hiện từ không còn là âm tiết tiếng Việt: hoàn nguyên toàn bộ phím gốc
    /// rồi khoá từ này lại cho tới khi hết từ.
    private func enforceSpelling() {
        guard spellCheck, !blocked else { return }
        guard !Syllable.isPlausiblePrefix(letters()) else { return }
        blocked = true
        restoreRawKeys()
    }

    private func restoreRawKeys() {
        var raw = ""
        for (i, u) in units.enumerated() {
            if i == toneAnchor, let t = toneRaw { raw += t }
            raw += u.raw
        }
        if let t = toneRaw, toneAnchor >= units.count { raw += t }

        units = raw.map {
            Unit(base: Character($0.lowercased()), upper: $0.isUppercase, raw: String($0))
        }
        tone = .none
        toneKey = nil
        toneRaw = nil
        toneAnchor = 0
    }

    // MARK: - Dựng chuỗi

    private func letterAt(_ i: Int) -> Character {
        Charset.compose(units[i].base, units[i].mark) ?? units[i].base
    }

    private func letters() -> [Character] {
        (0..<units.count).map(letterAt)
    }

    private func render() -> String {
        guard !units.isEmpty else { return "" }
        let toneIndex = tone == .none ? nil : tonePosition()

        var out = String()
        out.reserveCapacity(units.count)
        for i in units.indices {
            var c = letterAt(i)
            if i == toneIndex { c = Charset.applyTone(c, tone) }
            if units[i].upper {
                out.append(contentsOf: String(c).uppercased())
            } else {
                out.append(c)
            }
        }
        return out.precomposedStringWithCanonicalMapping
    }

    // MARK: - So sánh trước/sau

    /// `typed` là ký tự hệ thống sẽ tự chèn nếu ta không can thiệp. Chỉ được đi
    /// đường nhanh khi kết quả đúng bằng văn bản cũ cộng ký tự đó — "w" -> "ư"
    /// cũng dài hơn một ký tự nhưng không phải ký tự người dùng gõ.
    private func diff(from before: String, typed: Character) -> Edit {
        let after = render()
        if after.count == before.count + 1, after.hasPrefix(before), after.last == typed {
            return .pass
        }
        return rawDiff(before, after)
    }

    private func rawDiff(_ before: String, _ after: String) -> Edit {
        let o = Array(before), n = Array(after)
        var i = 0
        while i < o.count, i < n.count, o[i] == n[i] { i += 1 }
        return Edit(backspaces: o.count - i, insert: String(n[i...]), passthrough: false)
    }
}
