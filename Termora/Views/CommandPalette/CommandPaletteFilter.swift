import Foundation

/// Komut listesini arama sorgusuna göre süzen ve sıralayan saf mantık.
/// Görünüm bu fonksiyonların çıktısını olduğu gibi çizer; sıralama her zaman aynıdır.
@MainActor
enum CommandPaletteFilter {

    /// Son kullanılan komutlara verilen ek puan (brief: "Son kullanılan komutlar").
    /// En son çalıştırılan komut en yüksek ikramiyeyi alır; ikramiye eşit puanlı
    /// eşleşmelerde sırayı belirleyecek kadar büyük, açıkça daha iyi bir eşleşmeyi
    /// geçemeyecek kadar küçüktür.
    static let recencyBonus = 5

    /// Sorgu boşken son kullanılanların toplandığı bölüm başlığı.
    static let recentSectionTitle = "Recently Used"

    /// Sorguya uyan komutlar, en iyi eşleşme başta olmak üzere.
    /// Sorgu boşsa hiçbir komut elenmez: önce son kullanılanlar, sonra bildirim sırası.
    static func results(items: [CommandPaletteItem],
                        query: String,
                        recentIDs: [String]) -> [CommandPaletteResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return recentsFirst(items: items, recentIDs: recentIDs) }

        struct Scored {
            let result: CommandPaletteResult
            /// 0 = başlık eşleşmesi, 1 = yalnız kategori adı eşleşmesi.
            let kind: Int
            let score: Int
            let order: Int
        }

        let scored: [Scored] = items.enumerated().compactMap { order, item in
            let isRecent = recentIDs.contains(item.id)
            if let match = FuzzyMatcher.match(trimmed, in: item.title) {
                return Scored(result: CommandPaletteResult(item: item,
                                                           matchedIndices: match.matchedIndices,
                                                           isRecent: isRecent),
                              kind: 0,
                              score: match.score + bonus(for: item.id, in: recentIDs),
                              order: order)
            }
            // "theme" yazan kullanıcı tema komutlarını da görebilmeli. Kategori üzerinden
            // gelen eşleşmelerde başlıkta vurgulanacak karakter yoktur.
            if let match = FuzzyMatcher.match(trimmed, in: item.category.title) {
                return Scored(result: CommandPaletteResult(item: item,
                                                           matchedIndices: [],
                                                           isRecent: isRecent),
                              kind: 1,
                              score: match.score + bonus(for: item.id, in: recentIDs),
                              order: order)
            }
            return nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.order < rhs.order
            }
            .map(\.result)
    }

    /// Sonuçları başlıklı bölümlere ayırır. Bölümler sonuç sırasını BOZMAZ; her bölüm
    /// düz listenin bitişik bir dilimidir, böylece klavye seçimi düz indeksle çalışır.
    static func sections(for results: [CommandPaletteResult],
                         query: String) -> [CommandPaletteSection] {
        guard !results.isEmpty else { return [] }
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return [CommandPaletteSection(title: "Results", results: results)]
        }

        var sections: [CommandPaletteSection] = []
        var current: [CommandPaletteResult] = []
        var currentTitle: String?

        for result in results {
            let title = result.isRecent ? recentSectionTitle : result.item.category.title
            if currentTitle != title {
                if let currentTitle, !current.isEmpty {
                    sections.append(CommandPaletteSection(title: currentTitle, results: current))
                }
                currentTitle = title
                current = []
            }
            current.append(result)
        }
        if let currentTitle, !current.isEmpty {
            sections.append(CommandPaletteSection(title: currentTitle, results: current))
        }
        return sections
    }

    // MARK: - Yardımcılar

    private static func bonus(for id: String, in recentIDs: [String]) -> Int {
        guard let position = recentIDs.firstIndex(of: id) else { return 0 }
        return max(1, recencyBonus - position)
    }

    private static func recentsFirst(items: [CommandPaletteItem],
                                     recentIDs: [String]) -> [CommandPaletteResult] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recents = recentIDs.compactMap { byID[$0] }
        let recentIDSet = Set(recents.map(\.id))
        let rest = items.filter { !recentIDSet.contains($0.id) }
        return recents.map { CommandPaletteResult(item: $0, matchedIndices: [], isRecent: true) }
            + rest.map { CommandPaletteResult(item: $0, matchedIndices: []) }
    }
}

/// Palette çizilen bir başlık ve altındaki sonuçlar.
@MainActor
struct CommandPaletteSection: Identifiable {
    let title: String
    let results: [CommandPaletteResult]

    var id: String { title }
}
