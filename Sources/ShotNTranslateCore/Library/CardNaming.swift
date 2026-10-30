import Foundation

/// Default card titles use the calendar day as `ddMMyyyy`, then `_1`, `_2`, …
public enum CardNaming {
    public static let packageExtension = "sntcard"

    public static func dayStamp(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        let day = parts.day ?? 1
        let month = parts.month ?? 1
        let year = parts.year ?? 2000
        return String(format: "%02d%02d%04d", day, month, year)
    }

    /// Next unused title for the given day among already used titles (with or without extension).
    public static func nextTitle(existing: [String], on date: Date = Date(), calendar: Calendar = .current) -> String {
        let stamp = dayStamp(for: date, calendar: calendar)
        let used = Set(existing.map(normalizedTitle))
        var index = 1
        while used.contains("\(stamp)_\(index)") {
            index += 1
        }
        return "\(stamp)_\(index)"
    }

    public static func packageURL(named title: String, in folder: URL) -> URL {
        folder.appendingPathComponent(sanitizedFileName(title), isDirectory: true)
            .appendingPathExtension(packageExtension)
    }

    public static func sanitizedFileName(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") })
        let collapsed = cleaned
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "card" : collapsed
    }

    public static func title(fromPackageURL url: URL) -> String {
        var name = url.lastPathComponent
        if name.hasSuffix(".\(packageExtension)") {
            name = String(name.dropLast(packageExtension.count + 1))
        }
        return name
    }

    public static func normalizedTitle(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".\(packageExtension)") {
            name = String(name.dropLast(packageExtension.count + 1))
        }
        return name
    }
}
