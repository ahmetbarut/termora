import Foundation

/// briefs/3 "Durum Tasarımları" ▸ Error State.
///
/// Brief hatanın dört soruyu yanıtlamasını istiyor: ne başarısız oldu, muhtemel sebep,
/// kullanıcı ne yapabilir, teknik detay nasıl görüntülenir. Tip bunu ZORUNLU kılıyor —
/// üçü de gerekli alan, dördüncüsü isteğe bağlı.
struct ErrorStateContent: Equatable {
    /// Ne başarısız oldu.
    let title: String
    /// Muhtemel sebep.
    let reason: String
    /// Kullanıcı ne yapabilir. Somut ve uygulanabilir olmalı.
    let recovery: String
    /// Açılır alanda gösterilecek iç detay.
    ///
    /// İsteğe bağlı: her hatanın gösterilecek bir detayı yoktur ve boş bir "Details"
    /// bölümü açan hata, kullanıcıyı boşuna tıklatır.
    let technicalDetail: String?

    init(title: String, reason: String, recovery: String, technicalDetail: String? = nil) {
        self.title = title
        self.reason = reason
        self.recovery = recovery
        self.technicalDetail = technicalDetail
    }
}

/// briefs/3 "Durum Tasarımları" ▸ Empty State: tek cümlelik açıklama, birincil eylem,
/// gerekirse kısayol. Gereksiz illüstrasyon yok — bu yüzden tipte görsel alanı da yok.
struct EmptyStateContent: Equatable {
    let message: String
    /// En fazla BİR eylem. İkisi olsaydı hangisinin birincil olduğu belirsizleşirdi.
    let actionTitle: String?
    /// Eylemin kısayolu, varsa.
    let shortcut: String?

    init(message: String, actionTitle: String? = nil, shortcut: String? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.shortcut = shortcut
    }
}

/// briefs/3 "Durum Tasarımları" ▸ Loading State.
enum LoadingStateContent {
    /// Gösterge bu kadar bekledikten SONRA çıkar.
    ///
    /// briefs/3: *Shell birkaç yüz milisaniye içinde başlamıyorsa küçük bir durum
    /// göstergesi yeterlidir.* Hemen çıkan bir gösterge, hızlı işlemlerde ekranı
    /// titretir — kullanıcı bir şeyin belirip kaybolduğunu görür ve ne olduğunu anlamaz.
    static let delay: Duration = .milliseconds(400)
}

/// briefs/3 "Uygulama Metin Dili": *Belirsiz `OK` veya `Yes` butonları kullanılmamalıdır.*
enum StateActionTitle {
    private static let vague: Set<String> = ["ok", "yes", "no", "continue", "done", "cancel?"]

    /// Buton başlığı eylemi adlandırıyor mu.
    static func isVague(_ title: String) -> Bool {
        vague.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
