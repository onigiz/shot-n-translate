import Foundation

public enum CardSort: String, CaseIterable, Sendable, Identifiable {
    case nameAscending
    case nameDescending
    case createdNewest
    case createdOldest
    case modifiedNewest
    case modifiedOldest

    public var id: String { rawValue }

    public func sorted(_ cards: [LibraryCardSummary]) -> [LibraryCardSummary] {
        switch self {
        case .nameAscending:
            cards.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .nameDescending:
            cards.sorted { $0.title.localizedStandardCompare($1.title) == .orderedDescending }
        case .createdNewest:
            cards.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest:
            cards.sorted { $0.createdAt < $1.createdAt }
        case .modifiedNewest:
            cards.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedOldest:
            cards.sorted { $0.modifiedAt < $1.modifiedAt }
        }
    }
}
