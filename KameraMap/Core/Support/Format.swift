import Foundation

enum Format {
    static let russian = Locale(identifier: "ru_RU")

    private static let directions = [
        "север", "северо-восток", "восток", "юго-восток",
        "юг", "юго-запад", "запад", "северо-запад",
    ]

    static func nationalDigits(_ input: String) -> String {
        var digits = input.filter(\.isNumber)
        if digits.hasPrefix("998"), digits.count > 9 {
            digits.removeFirst(3)
        }
        return String(digits.prefix(9))
    }

    static func nationalPhone(_ digits: String) -> String {
        let characters = Array(digits.prefix(9))
        var groups: [String] = []
        var index = 0
        for size in [2, 3, 2, 2] where index < characters.count {
            let end = min(index + size, characters.count)
            groups.append(String(characters[index..<end]))
            index = end
        }
        return groups.joined(separator: " ")
    }

    static func lifetime(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 {
            return "\(rest) мин"
        }
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = russian
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(russian))
    }

    static func compass(_ heading: Int) -> String {
        let index = Int((Double(heading) / 45).rounded()) % directions.count
        return directions[(index + directions.count) % directions.count]
    }
}
