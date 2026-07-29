import Foundation

/// briefs/3 "Sidebar" ▸ Saved Commands: kullanıcının kaydettiği tek bir komut.
///
/// Diske yazılır (bu bir tercih, terminal geçmişi değil), ama komutun ÇIKTISI hiçbir
/// zaman saklanmaz — briefs/2 "Gizlilik" geçmişin kalıcılaşmamasını istiyor.
struct SavedCommand: Identifiable, Codable, Equatable {
    var id: UUID
    /// Listede görünen ad. Boş bırakılabilir; o zaman komutun kendisi gösterilir.
    var name: String
    var command: String
    /// Ne işe yaradığı. Kullanıcı altı ay sonra kendi komutunu tanıyabilmeli.
    var details: String
    var tags: [String]
    /// Komutun çalışacağı dizin; boşsa aktif panelin dizini.
    var workingDirectory: String?

    init(id: UUID = UUID(),
         name: String = "",
         command: String,
         details: String = "",
         tags: [String] = [],
         workingDirectory: String? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.details = details
        // Boş ve boşluklu etiketler burada düşer: liste ekranında görünmeyen ama
        // aramada eşleşen bir etiket, kullanıcının açıklayamayacağı bir sonuç üretir.
        self.tags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.workingDirectory = workingDirectory
    }

    /// Sentezlenmiş çözücü eksik anahtarda `keyNotFound` fırlatır; `LenientArray` o kaydı
    /// atar ve kullanıcı sessizce bir komut kaybeder. Her alan `decodeIfPresent` ile okunur.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        // Komut ZORUNLU: komutsuz bir kayıt hiçbir işe yaramaz.
        command = try container.decode(String.self, forKey: .command)
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
    }

    /// Adsız kayıt komutuyla anılır: listede boş bir satır, kullanıcının neyi kaydettiğini
    /// göremediği bir satırdır.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? command : trimmed
    }

    /// briefs/2 "Tehlikeli Komut Koruması": kayıt engellenmez ama işaretlenir.
    var isRisky: Bool { DangerousCommand.inspect(command) != nil }

    /// Ada, komuta ve etiketlere bakar — kullanıcı hangisini hatırlıyorsa onunla bulur.
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(trimmed) { return true }
        if command.localizedCaseInsensitiveContains(trimmed) { return true }
        return tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
