import Foundation

/// Built-in gõ tắt: viết tắt chat/văn phòng và địa danh thường gặp.
/// Triggers match the composed word (`ddc` → `đc`, `ddn` → `đn`).
enum DefaultMacros {
    static let entries: [MacroEntry] = merging(into: [])

    /// Add any missing built-in shortcuts without overwriting the user's.
    static func merging(into existing: [MacroEntry]) -> [MacroEntry] {
        var seen = Set(
            existing.map { $0.trigger.lowercased() }.filter { !$0.isEmpty }
        )
        var result = existing
        for (trigger, expansion) in pairs {
            let key = trigger.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(MacroEntry(trigger: trigger, expansion: expansion))
        }
        return sorted(result)
    }

    static func sorted(_ macros: [MacroEntry]) -> [MacroEntry] {
        macros.sorted {
            $0.trigger.compare($1.trigger, locale: vi) == .orderedAscending
        }
    }

    private static let vi = Locale(identifier: "vi_VN")

    /// ASCII + composed forms of the same shortcut (`dc`/`đc`) so Telex and
    /// already-accented typing both expand. Skip 1-letter keys and collisions
    /// with units (`kg`, `cm`) or real Vietnamese words (`na`, `la`).
    private static let pairs: [(String, String)] = [
        // Chat / văn phòng
        ("dc", "được"),
        ("đc", "được"),
        ("ko", "không"),
        ("kô", "không"),
        ("khg", "không"),
        ("hok", "không"),
        ("ng", "người"),
        ("nh", "nhưng"),
        ("nk", "những"),
        ("nx", "nữa"),
        ("cx", "cũng"),
        ("vs", "với"),
        ("ntn", "như thế nào"),
        ("bn", "bạn"),
        ("mk", "mình"),
        ("ln", "luôn"),
        ("lun", "luôn"),
        ("bh", "bây giờ"),
        ("hnay", "hôm nay"),
        ("hqua", "hôm qua"),
        ("nmai", "ngày mai"),
        ("kq", "kết quả"),
        ("nv", "nhân viên"),
        ("dt", "điện thoại"),
        ("đt", "điện thoại"),
        ("tg", "thời gian"),
        ("sl", "số lượng"),
        ("dchi", "địa chỉ"),
        ("đchi", "địa chỉ"),
        ("ngta", "người ta"),
        ("nhe", "nhé"),
        ("tks", "cảm ơn"),
        ("sn", "sinh nhật"),
        ("oh", "ồ"),
        ("òh", "ồ"),
        ("uh", "ừ"),
        ("ah", "à"),

        // Tổ chức / học đường
        ("vn", "Việt Nam"),
        ("tp", "thành phố"),
        ("clb", "câu lạc bộ"),
        ("htx", "hợp tác xã"),
        ("nxb", "Nhà xuất bản"),
        ("ubnd", "Ủy ban nhân dân"),
        ("thpt", "Trung học phổ thông"),
        ("thcs", "Trung học cơ sở"),
        ("dh", "đại học"),
        ("đh", "đại học"),
        ("bs", "bác sĩ"),
        ("lhq", "Liên Hợp Quốc"),
        ("tw", "Trung ương"),

        // Địa danh
        ("hn", "Hà Nội"),
        ("hcm", "Hồ Chí Minh"),
        ("tphcm", "TP. Hồ Chí Minh"),
        ("sg", "Sài Gòn"),
        ("dn", "Đà Nẵng"),
        ("đn", "Đà Nẵng"),
        ("hp", "Hải Phòng"),
        ("ct", "Cần Thơ"),
        ("hue", "Huế"),
        ("huế", "Huế"),
        ("nt", "Nha Trang"),
        ("vt", "Vũng Tàu"),
        ("hl", "Hạ Long"),
        ("dl", "Đà Lạt"),
        ("đl", "Đà Lạt"),
        ("pq", "Phú Quốc"),
        ("qn", "Quảng Ninh"),
        ("qnh", "Quy Nhơn"),
        ("bd", "Bình Dương"),
        ("dna", "Đồng Nai"),
        ("đna", "Đồng Nai"),
        ("th", "Thanh Hóa"),
        ("nb", "Ninh Bình"),
        ("py", "Phú Yên"),
        ("ag", "An Giang"),
        ("bt", "Bến Tre"),
        ("bl", "Bạc Liêu"),
        ("bg", "Bắc Giang"),
        ("hd", "Hải Dương"),
        ("hy", "Hưng Yên"),
        ("nd", "Nam Định"),
        ("tb", "Thái Bình"),
        ("qb", "Quảng Bình"),
        ("qt", "Quảng Trị"),
        ("qnam", "Quảng Nam"),
        ("qng", "Quảng Ngãi"),
        ("bth", "Bình Thuận"),
        ("ld", "Lâm Đồng"),
        ("lđ", "Lâm Đồng"),
        ("st", "Sóc Trăng"),
        ("tv", "Trà Vinh"),
    ]
}
