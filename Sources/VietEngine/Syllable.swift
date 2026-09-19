//  Syllable.swift
//  Phân tích cấu trúc âm tiết tiếng Việt: ÂM ĐẦU + VẦN(NGUYÊN ÂM + ÂM CUỐI).
//  Dùng cho hai việc:
//    1. Xác định vị trí đặt thanh điệu (kiểu cũ / kiểu mới).
//    2. Kiểm tra chính tả — từ chối bỏ dấu cho tổ hợp không phải tiếng Việt.

import Foundation

/// Kiểu đặt dấu thanh.
public enum ToneStyle: String, Sendable {
    /// "hoà", "thuý" — đặt dấu lên nguyên âm chính theo ngữ âm học.
    case modern
    /// "hòa", "thúy" — đặt dấu lên nguyên âm đầu của oa/oe/uy khi không có âm cuối.
    case classic
}

public enum Syllable {

    // MARK: - Bảng âm

    /// Âm đầu hợp lệ. "qu" và "gi" được xử lý riêng trong `parse`.
    static let onsets: Set<String> = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m",
        "n", "ng", "ngh", "nh", "p", "ph", "q", "qu", "r", "s", "t", "th", "tr",
        "v", "x",
    ]

    /// Âm cuối hợp lệ.
    static let codas: Set<String> = ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"]

    /// Nguyên âm (vần cái) -> chỉ số (0-based) của nguyên âm mang thanh, KIỂU MỚI.
    /// Ba tổ hợp oa/oe/uy được đánh dấu riêng vì kiểu cũ đặt khác (xem `ambiguous`).
    static let nuclei: [String: Int] = [
        // một nguyên âm
        "a": 0, "ă": 0, "â": 0, "e": 0, "ê": 0, "i": 0,
        "o": 0, "ô": 0, "ơ": 0, "u": 0, "ư": 0, "y": 0,
        // hai nguyên âm
        "ai": 0, "ao": 0, "au": 0, "ay": 0, "âu": 0, "ây": 0,
        "eo": 0, "êu": 0,
        "ia": 0, "iê": 1, "iu": 0,
        "oa": 1, "oă": 1, "oe": 1, "oi": 0, "oo": 0, "ôi": 0, "ơi": 0,
        "ua": 0, "uâ": 1, "uă": 1, "uê": 1, "ui": 0, "uô": 1, "uơ": 1, "uy": 1,
        "ưa": 0, "ưi": 0, "ươ": 1, "ưu": 0,
        "yê": 1,
        // ba nguyên âm
        "iêu": 1, "oai": 1, "oao": 1, "oay": 1, "oeo": 1,
        "uay": 1, "uây": 1, "uôi": 1, "uya": 1, "uyê": 2, "uyu": 1,
        "ươi": 1, "ươu": 1, "yêu": 1,
    ]

    /// Các vần mà kiểu cũ và kiểu mới đặt dấu khác nhau — chỉ khi KHÔNG có âm cuối.
    /// hoà/hòa, hoè/hòe, thuý/thúy.
    static let ambiguous: Set<String> = ["oa", "oe", "uy"]

    // MARK: - Tập tiền tố (cho kiểm tra chính tả khi đang gõ dở)

    private static func prefixes(of words: some Sequence<String>) -> Set<String> {
        var out: Set<String> = [""]
        for w in words {
            var acc = ""
            for c in w { acc.append(c); out.insert(acc) }
        }
        return out
    }

    /// Tiền tố âm đầu hợp lệ: "n", "ng", "ngh"...
    static let onsetPrefixes: Set<String> = prefixes(of: onsets)

    /// Tiền tố âm cuối hợp lệ: "c", "ch", "n", "ng", "nh"...
    static let codaPrefixes: Set<String> = prefixes(of: codas)

    /// Tiền tố nguyên âm, ĐÃ BỎ DẤU PHỤ. Cần bỏ dấu phụ vì khi gõ "tieengs" thì
    /// ở bước "tie" người dùng chưa gõ xong "iê" — "ie" phải được coi là hợp lệ.
    static let nucleusPrefixesStripped: Set<String> = prefixes(of: nuclei.keys.map(Charset.stripMarks))

    /// Nguyên âm đã bỏ dấu phụ -> dạng chuẩn có dấu phụ, để tra `nuclei` khi
    /// người dùng gõ thiếu dấu phụ ("tieng" + "s" -> "tiéng").
    /// Ưu tiên dạng vốn đã không có dấu phụ ("ua" thắng "uâ"/"uă").
    static let nucleusByStripped: [String: String] = {
        var out: [String: String] = [:]
        for key in nuclei.keys.sorted() {
            let s = Charset.stripMarks(key)
            if let existing = out[s] {
                // dạng không có dấu phụ luôn được ưu tiên
                if existing == s { continue }
                if key == s { out[s] = key }
            } else {
                out[s] = key
            }
        }
        return out
    }()

    // MARK: - Phân tích

    public struct Parts: Equatable, Sendable {
        /// Số chữ cái thuộc âm đầu.
        public var onsetLength: Int
        /// Chuỗi nguyên âm, giữ nguyên dấu phụ.
        public var nucleus: String
        /// Âm cuối.
        public var coda: String
    }

    /// Tách âm tiết đã hoàn chỉnh. Trả về nil nếu không phải âm tiết tiếng Việt.
    /// `letters` là các chữ cái thường, đã gắn dấu phụ, CHƯA có thanh điệu.
    public static func parse(_ letters: [Character]) -> Parts? {
        guard !letters.isEmpty else { return nil }

        // 1. Âm đầu: khớp dài nhất, tối đa 3 chữ cái.
        var onsetLength = 0
        for len in stride(from: min(3, letters.count), through: 1, by: -1) {
            let candidate = String(letters[0..<len])
            if onsets.contains(candidate), !candidate.isEmpty {
                // Không lấy nguyên âm làm âm đầu.
                if candidate.allSatisfy({ !Charset.isVowel($0) }) || candidate == "gi" || candidate == "qu" {
                    onsetLength = len
                    break
                }
            }
        }

        // "qu" + nguyên âm -> u thuộc âm đầu ("quả" = qu + a).
        if onsetLength == 1, letters[0] == "q", letters.count > 1, letters[1] == "u",
           letters.count > 2, Charset.isVowel(letters[2]) {
            onsetLength = 2
        }
        // "gi" + nguyên âm khác -> i thuộc âm đầu ("giá" = gi + a).
        // Nếu sau "gi" không còn nguyên âm nào thì i là nguyên âm chính ("gì").
        if onsetLength == 2, letters[0] == "g", letters[1] == "i" {
            if letters.count < 3 || !Charset.isVowel(letters[2]) { onsetLength = 1 }
        }

        // 2. Nguyên âm: dãy nguyên âm liền nhau.
        var i = onsetLength
        var nucleus = ""
        while i < letters.count, Charset.isVowel(letters[i]) {
            nucleus.append(letters[i]); i += 1
        }
        guard !nucleus.isEmpty else { return nil }

        // 3. Âm cuối: phần còn lại, không được chứa nguyên âm.
        let coda = String(letters[i...])
        guard codas.contains(coda) else { return nil }
        guard lookupNucleus(nucleus) != nil else { return nil }

        return Parts(onsetLength: onsetLength, nucleus: nucleus, coda: coda)
    }

    /// Tra nguyên âm: khớp chính xác trước, sau đó khớp "nới lỏng" (bỏ dấu phụ).
    /// Trả về (khoá chuẩn, chỉ số thanh kiểu mới).
    static func lookupNucleus(_ nucleus: String) -> (key: String, index: Int)? {
        if let idx = nuclei[nucleus] { return (nucleus, idx) }
        let stripped = Charset.stripMarks(nucleus)
        if let key = nucleusByStripped[stripped], let idx = nuclei[key] { return (key, idx) }
        return nil
    }

    /// Vị trí (chỉ số trong `letters`) của chữ cái mang thanh điệu.
    /// Trả về nil nếu âm tiết không hợp lệ.
    public static func tonePosition(_ letters: [Character], style: ToneStyle) -> Int? {
        guard let p = parse(letters) else { return nil }
        guard let (key, modernIndex) = lookupNucleus(p.nucleus) else { return nil }

        // Quy tắc 1: nếu trong vần có nguyên âm mang dấu phụ thì thanh đặt lên
        // nguyên âm mang dấu phụ CUỐI CÙNG. Đúng cho cả hai kiểu.
        //   iê -> ê, uô -> ô, ươ -> ơ, uyê -> ê, oă -> ă, ưa -> ư
        var marked: Int? = nil
        for (offset, c) in p.nucleus.enumerated() where Charset.stripMark(c) != c {
            marked = offset
        }
        if let m = marked { return p.onsetLength + m }

        // Quy tắc 2: không có dấu phụ nhưng có âm cuối -> nguyên âm cuối cùng.
        //   hoàng, oanh, huỳnh
        if !p.coda.isEmpty { return p.onsetLength + p.nucleus.count - 1 }

        // Quy tắc 3: không dấu phụ, không âm cuối -> tra bảng.
        //   Riêng oa/oe/uy khác nhau giữa hai kiểu.
        if style == .classic, ambiguous.contains(key) { return p.onsetLength }
        return p.onsetLength + modernIndex
    }

    // MARK: - Kiểm tra khi đang gõ dở

    /// Chuỗi chữ cái này còn có thể trở thành âm tiết tiếng Việt không?
    /// Khoan dung hơn `parse` vì từ đang gõ dở ("ngh", "tie", "ngu").
    public static func isPlausiblePrefix(_ letters: [Character]) -> Bool {
        if letters.isEmpty { return true }

        var i = 0
        // Ăn phần phụ âm đầu.
        var onset = ""
        while i < letters.count, !Charset.isVowel(letters[i]) {
            onset.append(Charset.stripMark(letters[i])); i += 1
        }
        guard onsetPrefixes.contains(onset) else { return false }
        // "gi" + một nguyên âm khác: i thuộc âm đầu ("giỏi" = gi + oi).
        // Khi chỉ mới có "gi", i vẫn có thể là nguyên âm chính của "gì".
        if onset == "g", i + 1 < letters.count, letters[i] == "i",
           Charset.isVowel(letters[i + 1]) {
            onset = "gi"
            i += 1
        }
        if i == letters.count { return true }

        // Ăn dãy nguyên âm.
        var nucleus = ""
        while i < letters.count, Charset.isVowel(letters[i]) {
            nucleus.append(Charset.stripMark(letters[i])); i += 1
        }
        guard nucleusPrefixesStripped.contains(nucleus) else { return false }
        if i == letters.count { return true }

        // Ăn âm cuối. Sau âm cuối không được có nguyên âm nữa.
        var coda = ""
        while i < letters.count {
            let c = letters[i]
            if Charset.isVowel(c) { return false }
            coda.append(Charset.stripMark(c)); i += 1
        }
        return codaPrefixes.contains(coda)
    }
}
