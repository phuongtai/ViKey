import Testing
@testable import VietEngine

/// Mô phỏng đúng những gì lớp event tap làm: giữ một bản sao văn bản đang hiển
/// thị, áp dụng `Edit` lên đó, rồi đối chiếu với trạng thái trong engine.
/// Nếu giao thức xoá/chèn sai ở bất kỳ bước nào, phép so sánh dưới sẽ bắt được.
final class Simulator {
    let engine = TelexEngine()
    private(set) var text: [Character] = []
    private var wordStart = 0

    init(style: ToneStyle = .modern, spellCheck: Bool = true) {
        engine.style = style
        engine.spellCheck = spellCheck
    }

    /// `keys` dùng "<" cho phím Backspace, khoảng trắng để ngắt từ.
    @discardableResult
    func type(_ keys: String, sourceLocation: SourceLocation = #_sourceLocation) -> String {
        for ch in keys {
            if ch == "<" {
                apply(engine.deleteBackward(), fallback: nil, isBackspace: true)
            } else if ch.isLetter {
                apply(engine.input(ch, upper: ch.isUppercase), fallback: ch, isBackspace: false)
            } else {
                _ = engine.input(ch, upper: false)   // ngắt từ
                text.append(ch)
                wordStart = text.count
                continue
            }
            #expect(String(text[wordStart...]) == engine.currentText,
                    "engine lệch với văn bản hiển thị sau phím '\(ch)' trong \"\(keys)\"",
                    sourceLocation: sourceLocation)
            if engine.currentText.isEmpty { wordStart = text.count }
        }
        return String(text)
    }

    private func apply(_ edit: Edit, fallback: Character?, isBackspace: Bool) {
        if edit.passthrough {
            if isBackspace {
                if text.count > wordStart { text.removeLast() }
            } else if let f = fallback {
                text.append(f)
            }
            return
        }
        precondition(edit.backspaces <= text.count - wordStart, "xoá vượt phạm vi từ hiện tại")
        text.removeLast(edit.backspaces)
        text.append(contentsOf: edit.insert)
    }
}

private func telex(_ keys: String, style: ToneStyle = .modern, spellCheck: Bool = true,
                   sourceLocation: SourceLocation = #_sourceLocation) -> String {
    Simulator(style: style, spellCheck: spellCheck).type(keys, sourceLocation: sourceLocation)
}

// MARK: - Dấu phụ và thanh điệu

@Test("Dấu phụ cơ bản")
func basicMarks() {
    #expect(telex("aa") == "â")
    #expect(telex("ee") == "ê")
    #expect(telex("oo") == "ô")
    #expect(telex("aw") == "ă")
    #expect(telex("ow") == "ơ")
    #expect(telex("uw") == "ư")
    #expect(telex("dd") == "đ")
    #expect(telex("did") == "đi")
    #expect(telex("chuaw") == "chưa")
    #expect(telex("w") == "ư")
    #expect(telex("tw") == "tư")
    #expect(telex("uow") == "ươ")
}

@Test("Thanh điệu cơ bản")
func basicTones() {
    #expect(telex("as") == "á")
    #expect(telex("af") == "à")
    #expect(telex("ar") == "ả")
    #expect(telex("ax") == "ã")
    #expect(telex("aj") == "ạ")
    #expect(telex("asf") == "à")   // đổi thanh
    #expect(telex("asz") == "a")   // z bỏ thanh
}

@Test("Gõ lại phím biến đổi thì trả lại chữ gốc")
func undoByRepeatingKey() {
    #expect(telex("aaa") == "aa")
    #expect(telex("eee") == "ee")
    #expect(telex("ooo") == "oo")
    #expect(telex("ddd") == "dd")
    #expect(telex("aww") == "aw")
    #expect(telex("uww") == "uw")
    #expect(telex("ass") == "as")
    #expect(telex("Sess") == "Ses")
}

// MARK: - Từ thật

@Test("Từ thông dụng", arguments: [
    ("tieengs", "tiếng"),
    ("vieejt", "việt"),
    ("nam", "nam"),
    ("ddaays", "đấy"),
    ("nguyeenx", "nguyễn"),
    ("hoangf", "hoàng"),
    ("khoongr", "khổng"),
    ("cuar", "của"),
    ("quar", "quả"),
    ("quyeenr", "quyển"),
    ("quoocs", "quốc"),
    ("giaf", "già"),
    ("gif", "gì"),
    ("gioir", "giỏi"),
    ("giuwx", "giữ"),
    ("gieengs", "giếng"),
    ("dduowngf", "đường"),
    ("nguowif", "người"),
    ("nguwowif", "người"),
    ("ruowuj", "rượu"),
    ("chuyeenr", "chuyển"),
    ("hoawcj", "hoặc"),
    ("tuaans", "tuấn"),
    ("cuoocj", "cuộc"),
    ("muonwj", "mượn"),
    ("anh", "anh"),
    ("casch", "cách"),
    ("huynhf", "huỳnh"),
    ("xoasy", "xoáy"),
    ("chieeuf", "chiều"),
    ("nghieemj", "nghiệm"),
    ("thuowng", "thương"),
])
func commonWords(keys: String, want: String) {
    #expect(telex(keys) == want, "gõ \"\(keys)\"")
}

@Test("Cả câu")
func sentence() {
    #expect(telex("Tieengs Vieejt raats ddepj") == "Tiếng Việt rất đẹp")
    #expect(telex("xin chaof cacs banj") == "xin chào các bạn")
}

@Test("Chữ hoa")
func uppercase() {
    #expect(telex("Tieengs") == "Tiếng")
    #expect(telex("TIEENGS") == "TIẾNG")
    #expect(telex("DDaf") == "Đà")
}

// MARK: - Vị trí dấu thanh

@Test("Kiểu mới và kiểu cũ")
func toneStyles() {
    #expect(telex("hoaf", style: .modern) == "hoà")
    #expect(telex("hoaf", style: .classic) == "hòa")
    #expect(telex("thuys", style: .modern) == "thuý")
    #expect(telex("thuys", style: .classic) == "thúy")
    #expect(telex("hoef", style: .modern) == "hoè")
    #expect(telex("hoef", style: .classic) == "hòe")
    // Có âm cuối -> hai kiểu trùng nhau.
    #expect(telex("hoangf", style: .classic) == "hoàng")
    #expect(telex("huynhf", style: .classic) == "huỳnh")
    // Nguyên âm có dấu phụ -> hai kiểu trùng nhau.
    #expect(telex("cuoocj", style: .classic) == "cuộc")
}

// MARK: - Kiểm tra chính tả

@Test("Kiểm tra chính tả giữ nguyên từ tiếng Anh", arguments: [
    "xyzs", "email", "emails", "hello", "github", "sandbox", "android",
    "commit", "branch", "merge", "config", "import", "export", "default",
    "system", "network", "keyboard", "monitor", "compiler", "server",
    "terminal", "insert", "world", "windows", "docker", "python",
    "golang", "client", "update", "delete", "select", "folder", "image",
    "video", "photo", "script", "pointer", "number", "letter", "render",
    "screen", "laptop", "browser", "channel",
])
func spellCheckKeepsEnglishIntact(word: String) {
    #expect(telex(word) == word)
}

/// Phím bị "ăn" làm dấu rồi dấu bị từ chối thì phải trả lại nguyên văn,
/// nếu không "merge" sẽ ra "mege" — mất hẳn chữ r.
@Test("Hoàn nguyên phím gốc khi từ chối bỏ dấu")
func restoresRawKeys() {
    #expect(telex("merge") == "merge")
    #expect(telex("worl") == "worl")
    #expect(telex("defa") == "defa")
}

/// Những va chạm này là ĐẶC TÍNH của Telex chứ không phải lỗi: kết quả vẫn là
/// âm tiết tiếng Việt hợp lệ nên kiểm tra chính tả không có căn cứ để từ chối.
/// Unikey, OpenKey và EVKey đều cho kết quả y hệt. Cách xử lý: tắt tiếng Việt
/// bằng phím tắt trước khi gõ.
@Test("Va chạm cố hữu của Telex", arguments: [
    ("test", "tét"),
    ("music", "muíc"),
    ("swift", "sừit"),
    ("pass", "pas"),
    ("message", "mesage"),
    ("password", "pasword"),
])
func inherentTelexCollisions(word: String, want: String) {
    #expect(telex(word) == want)
}

// MARK: - Backspace

@Test("Backspace luôn đồng bộ")
func backspace() {
    #expect(telex("tieengs<") == "tiến")
    #expect(telex("aa<") == "")
    #expect(telex("dd<") == "")
    #expect(telex("tieengf<gs") == "tiếng")
}

// MARK: - Bất biến

/// Với chuỗi phím ngẫu nhiên, engine và văn bản hiển thị không bao giờ được lệch.
@Test("Không bao giờ mất đồng bộ")
func neverDesynchronises() {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzAEOWD< ")
    for _ in 0..<5000 {
        let n = Int.random(in: 1...14)
        let keys = String((0..<n).map { _ in alphabet.randomElement()! })
        _ = telex(keys)
    }
}
