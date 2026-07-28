import Foundation

/// Komut paletinin arama motoru (brief 3, "Komut Paleti Tasarımı" → "Hızlı fuzzy search").
///
/// Sorgu, adayın bir ALT DİZİSİ olmalıdır: harfler sırayı bozmadan bulunabilmelidir.
/// Puanlama, insanın beklediği eşleşmeleri öne çıkarır — kelime başlangıçları ve bitişik
/// harf dizileri yüksek, araya giren her karakter düşük puan alır.
///
/// Arama uzayı küçüktür (komut başlıkları), bu yüzden açgözlü tarama yerine tüm yolları
/// gezen bir dinamik programlama kullanılır: "xa b ab" içinde "ab" sorgusu soldaki dağınık
/// eşleşmeyi değil, sondaki bitişik çifti bulur. Aynı girdi her zaman aynı çıktıyı verir.
enum FuzzyMatcher {

    struct Match: Equatable, Sendable {
        let score: Int
        /// Eşleşen karakterlerin ADAY içindeki indeksleri (artan sırada). Listede vurgulama
        /// bu indeksleri kullanır.
        let matchedIndices: [Int]
    }

    // MARK: - Puanlama sabitleri

    /// Eşleşen her karakterin taban puanı.
    static let characterScore = 1
    /// Adayın ilk karakterini yakalayan eşleşme.
    static let firstCharacterBonus = 8
    /// Kelime başına ("New **T**ab", "new**T**ab") denk gelen eşleşme.
    static let wordStartBonus = 6
    /// Bir öncekiyle bitişik eşleşme.
    static let consecutiveBonus = 5
    /// Atlanan her karakterin bedeli.
    static let gapPenalty = 1

    /// Sorgu adayın içinde bulunuyorsa en iyi eşleşmeyi döndürür, yoksa `nil`.
    /// Boş sorgu (yalnız boşluklardan oluşan sorgu dahil) nötr puanlı boş bir eşleşmedir:
    /// palet, arama kutusu boşken tüm komutları listeler.
    static func match(_ query: String, in candidate: String) -> Match? {
        // Küçük harfe çevirme karakter karakter yapılır ve sonuç String olarak saklanır:
        // bazı karakterlerin küçük harfi TEK karakter değildir ("İ" → "i̇"), `Character(...)`
        // ile daraltmak çökerdi. String karşılaştırması bu tuzağı tamamen ortadan kaldırır.
        let queryCharacters = Array(query.trimmingCharacters(in: .whitespaces))
            .map { String($0).lowercased() }
        guard !queryCharacters.isEmpty else { return Match(score: 0, matchedIndices: []) }

        let candidateCharacters = Array(candidate)
        guard queryCharacters.count <= candidateCharacters.count else { return nil }
        let lowercasedCandidate = candidateCharacters.map { String($0).lowercased() }

        var solver = Solver(query: queryCharacters,
                            candidate: candidateCharacters,
                            lowercasedCandidate: lowercasedCandidate)
        return solver.solve()
    }

    // MARK: - Çözücü

    /// `best[qi][ci]`: sorgunun `qi`'den sonrasını, adayın `ci`'sinden itibaren eşleştirmenin
    /// en iyi puanı. `ci` konumundaki eşleşme "bitişik" sayılır, çünkü bu tabloya yalnızca
    /// bir önceki eşleşmenin hemen ardından girilir.
    private struct Solver {
        /// Sorgu karakterleri, küçük harfe çevrilmiş hâlleriyle.
        let query: [String]
        /// Adayın ORİJİNAL karakterleri (kelime başı tespiti büyük/küçük harfe bakar).
        let candidate: [Character]
        let lowercasedCandidate: [String]
        /// nil = henüz hesaplanmadı, .some(nil) = eşleşme yok.
        var memo: [[Int??]]

        init(query: [String], candidate: [Character], lowercasedCandidate: [String]) {
            self.query = query
            self.candidate = candidate
            self.lowercasedCandidate = lowercasedCandidate
            memo = Array(repeating: Array(repeating: Int??.none, count: candidate.count + 1),
                         count: query.count + 1)
        }

        mutating func solve() -> Match? {
            guard let score = best(queryIndex: 0, from: 0) else { return nil }
            return Match(score: score, matchedIndices: path())
        }

        mutating func best(queryIndex: Int, from start: Int) -> Int? {
            if queryIndex == query.count { return 0 }
            if start >= candidate.count { return nil }
            if let cached = memo[queryIndex][start] { return cached }

            var result: Int?
            for position in start..<candidate.count
            where lowercasedCandidate[position] == query[queryIndex] {
                guard let rest = best(queryIndex: queryIndex + 1, from: position + 1) else { continue }
                let total = stepScore(queryIndex: queryIndex, position: position, start: start) + rest
                if result == nil || total > result! { result = total }
            }
            memo[queryIndex][start] = .some(result)
            return result
        }

        /// Tek bir eşleşmenin puanı: taban + konum ikramiyeleri − atlanan karakterler.
        func stepScore(queryIndex: Int, position: Int, start: Int) -> Int {
            var score = FuzzyMatcher.characterScore
            if position == 0 {
                score += FuzzyMatcher.firstCharacterBonus
            } else if isWordStart(position) {
                score += FuzzyMatcher.wordStartBonus
            }
            if queryIndex > 0 && position == start {
                score += FuzzyMatcher.consecutiveBonus
            }
            score -= (position - start) * FuzzyMatcher.gapPenalty
            return score
        }

        func isWordStart(_ position: Int) -> Bool {
            guard position > 0 else { return true }
            let previous = candidate[position - 1]
            if previous.isLetter == false && previous.isNumber == false { return true }
            return previous.isLowercase && candidate[position].isUppercase
        }

        /// En iyi puanı üreten yolu tabloyu ikinci kez gezerek geri kurar.
        mutating func path() -> [Int] {
            var indices: [Int] = []
            var start = 0
            for queryIndex in query.indices {
                guard let target = best(queryIndex: queryIndex, from: start) else { break }
                var chosen: Int?
                for position in start..<candidate.count
                where lowercasedCandidate[position] == query[queryIndex] {
                    guard let rest = best(queryIndex: queryIndex + 1, from: position + 1) else { continue }
                    if stepScore(queryIndex: queryIndex, position: position, start: start) + rest == target {
                        chosen = position
                        break
                    }
                }
                guard let chosen else { break }
                indices.append(chosen)
                start = chosen + 1
            }
            return indices
        }
    }
}
