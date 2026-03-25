import Foundation

extension Date {
    /// 格式化为本地化日期字符串（如 "2024年3月25日"）
    /// DateFormatter 实例化成本高（~1-5ms），使用静态缓存避免列表滚动时重复创建
    var localizedDateString: String {
        Date.mediumDateFormatter.string(from: self)
    }

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale.current
        return f
    }()

    /// 格式化为年龄字符串（如 "28岁"）
    var ageString: String {
        let years = Calendar.current.dateComponents([.year], from: self, to: Date()).year ?? 0
        return "\(years)岁"
    }

    /// 是否为今天
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}
