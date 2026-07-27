import Foundation

/// SwiftTerm `searchMatchSummary` çıktısının uygulama içi karşılığı.
/// `index` 1 tabanlıdır; aktif eşleşme yoksa 0'dır.
struct SearchSummary: Equatable {
    var index: Int
    var total: Int

    static let empty = SearchSummary(index: 0, total: 0)
}

/// Arama çubuğundaki "2/14" sayacını üretir.
enum SearchSummaryFormatter {
    static func text(_ summary: SearchSummary) -> String {
        guard summary.total > 0 else { return "0/0" }
        let index = min(max(summary.index, 0), summary.total)
        return "\(index)/\(summary.total)"
    }
}

/// Arama isteğinin SwiftTerm'den bağımsız gösterimi (SwiftTerm sınırı dar tutulur).
struct TerminalSearchQuery: Equatable {
    var term: String
    var caseSensitive: Bool
    var usesRegex: Bool
    var wholeWord: Bool

    init(term: String, caseSensitive: Bool = false, usesRegex: Bool = false, wholeWord: Bool = false) {
        self.term = term
        self.caseSensitive = caseSensitive
        self.usesRegex = usesRegex
        self.wholeWord = wholeWord
    }
}
