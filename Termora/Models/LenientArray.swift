import Foundation

/// Bir JSON dizisini ÖĞE ÖĞE çözer: çözülemeyen öğe atlanır, geri kalanlar korunur.
///
/// Neden: `[T].self` ile çözerken tek bir bozuk öğe bütün diziyi düşürür. Depolar bunu
/// "blob bozuk" sayar, yedeğe taşıyıp listeyi boşaltır — yani tek kayıt yüzünden
/// kullanıcının TÜM profilleri / workspace'leri gider. Burada bozulma öğe düzeyinde
/// sınırlanır.
///
/// Nasıl: `FailableElement` hiçbir zaman fırlatmaz, bu yüzden çözücünün imleci bozuk
/// öğede de ilerler (fırlatan bir `decode` imleci ilerletmez ve döngü sonsuza girerdi).
/// Yakalanan hatalar `failures` içinde çağırana verilir; loglamak çağıranın işidir,
/// çünkü hangi kategoriye yazılacağını yalnız o bilir.
struct LenientArray<Element: Decodable>: Decodable {
    let elements: [Element]
    let failures: [any Error]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var failures: [any Error] = []
        if let count = container.count {
            elements.reserveCapacity(count)
        }
        while !container.isAtEnd {
            switch try container.decode(FailableElement<Element>.self).result {
            case let .success(element):
                elements.append(element)
            case let .failure(error):
                failures.append(error)
            }
        }
        self.elements = elements
        self.failures = failures
    }

    /// Loglanabilir özet. `DecodingError` metinleri yalnız tip/alan adı ve dizin taşır,
    /// kullanıcı verisi taşımaz; bu yüzden log'a açık (public) yazılabilir.
    var failureSummary: String {
        failures.map { String(describing: $0) }.joined(separator: " | ")
    }
}

private struct FailableElement<Element: Decodable>: Decodable {
    let result: Result<Element, any Error>

    init(from decoder: Decoder) throws {
        result = Result { try Element(from: decoder) }
    }
}
