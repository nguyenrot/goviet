import Foundation

/// v0.2.5 accidentally seeded expansion macros (đc→được, đn→Đà Nẵng, …).
/// v3 strips those exact pairs so abbreviations stay abbreviated.
enum DefaultMacros {
    static func stripSeeded(from existing: [MacroEntry]) -> [MacroEntry] {
        let seeded = Set(pairs.map { SeededMacro(trigger: $0.0, expansion: $0.1) })
        return existing.filter {
            !seeded.contains(SeededMacro(trigger: $0.trigger, expansion: $0.expansion))
        }
    }

    static func sorted(_ macros: [MacroEntry]) -> [MacroEntry] {
        macros.sorted {
            $0.trigger.compare($1.trigger, locale: vi) == .orderedAscending
        }
    }

    private static let vi = Locale(identifier: "vi_VN")

    private struct SeededMacro: Hashable {
        let trigger: String
        let expansion: String

        init(trigger: String, expansion: String) {
            self.trigger = trigger.lowercased()
            self.expansion = expansion
        }
    }

    private static let pairs: [(String, String)] = [
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
