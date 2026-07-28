import Foundation

struct TerminalProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var shellPath: String? = nil
    var startupDirectory: String? = nil
    var startupCommand: String? = nil
    var fontName: String? = nil
    var fontSize: Double? = nil
    var themeID: String? = nil
    var environment: [String: String] = [:]

    /// briefs/2 "Bildirimler": uzun işlem bildirimleri profil bazında KAPATILABİLİR.
    ///
    /// "Devral / aç / kapat" üçlüsü yerine tek yönlü bir susturma: brief yalnızca kapatmayı
    /// istiyor ve global anahtar kapalıyken bir profilin bildirim AÇMASI, kullanıcının
    /// "bildirim istemiyorum" kararını profil ayarından sessizce delerdi.
    var suppressesCommandNotifications: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, shellPath, startupDirectory, startupCommand, fontName, fontSize, themeID, environment
        case suppressesCommandNotifications
    }
}

// MARK: - İleri uyumlu çözme

extension TerminalProfile {
    /// Elle yazılmış çözücü: sentezlenmiş `init(from:)` özellik varsayılanlarını YOK SAYAR,
    /// eksik anahtarda `keyNotFound` fırlatır. Sentezlenmiş hâlde kalsaydı modele yeni bir
    /// alan eklemek kullanıcının diskteki eski blob'unu `ProfileStore` gözünde bozuk yapar
    /// ve TÜM profilleri silinirdi. Bilinmeyen alanlar (yeni sürümde yazılmış blob)
    /// keyed container tarafından zaten yok sayılır.
    ///
    /// `init(from:)` uzantıda durur ki üye-bazlı (memberwise) init sentezlenmeye devam etsin.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `id` ve `name` için varsayılan ÜRETİLMEZ: taze bir UUID `Workspace.profileID`
        // bağını sessizce koparır, uydurma bir ad da kullanıcıya yalan söyler. Bu alanlar
        // yoksa kayıt çözülemez; çağıran (bkz. ProfileStore) yalnız o kaydı atlar.
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shellPath = try container.decodeIfPresent(String.self, forKey: .shellPath)
        startupDirectory = try container.decodeIfPresent(String.self, forKey: .startupDirectory)
        startupCommand = try container.decodeIfPresent(String.self, forKey: .startupCommand)
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID)
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        suppressesCommandNotifications = try container
            .decodeIfPresent(Bool.self, forKey: .suppressesCommandNotifications) ?? false
    }
}
