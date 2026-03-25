import Foundation

extension Date {
    /// 格式化为本地化日期字符串（如 "2024年3月25日"）
    var localizedDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: self)
    }

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
