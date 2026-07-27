import Foundation

/// `TerminalProfile.environment` sözlüğünün UI'da sıralı ve düzenlenebilir hâli.
/// Sözlük sırasız olduğu için satırların kararlı kimliğe ihtiyacı vardır.
struct EnvironmentEntry: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

enum EnvironmentEditing {

    /// Sözlüğü anahtara göre sıralı satır listesine çevirir.
    static func entries(from dictionary: [String: String]) -> [EnvironmentEntry] {
        dictionary.keys.sorted().map { key in
            EnvironmentEntry(key: key, value: dictionary[key] ?? "")
        }
    }

    /// Satırları sözlüğe çevirir: anahtarlar kırpılır, boş anahtarlı satırlar atılır,
    /// aynı anahtar birden çok kez varsa son satır kazanır.
    static func dictionary(from entries: [EnvironmentEntry]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[key] = entry.value
        }
        return result
    }
}
