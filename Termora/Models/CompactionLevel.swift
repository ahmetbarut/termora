import CoreGraphics
import Foundation

/// briefs/3 "Küçük Pencere Davranışı"nın daralma sırası.
///
/// Brief beş adım sayıyor ve sonuncusu şart: *Terminal alanı korunmalı.* Karar saf bir
/// tip olarak duruyor — hangi bilginin önce düşeceği, pencere çizilmeden sınanabilmeli.
///
/// Sıra keyfi değil, ne işe yaradıklarına göre: en seyrek bakılan (terminal ölçüsü)
/// önce, kullanıcının nerede olduğunu söyleyen (çalışma dizini) en son düşer.
enum CompactionLevel: Equatable {
    case full
    case reduced
    case minimal

    /// Eşikler pencere genişliğine göre. `minWidth` (720) alt sınır olduğu için
    /// `minimal` her zaman ulaşılabilir bir durumdur.
    init(availableWidth: Double) {
        switch availableWidth {
        case ..<820: self = .minimal
        case ..<1024: self = .reduced
        default: self = .full
        }
    }

    /// Kullanıcı hangi klasörde olduğunu göremezse durum çubuğu hiçbir işe yaramaz;
    /// bu yüzden her düzeyde kalır.
    var showsWorkingDirectory: Bool { true }

    /// Nerede olduğunu bilmek, hangi dalda olduğunu bilmekten önce gelir.
    var showsGitDetail: Bool { self != .minimal }

    /// Kullanıcının en seyrek baktığı bilgi; ilk düşen bu.
    var showsTerminalSize: Bool { self == .full }

    /// briefs/3 dördüncü adım: *Sidebar otomatik kapanabilmeli.*
    ///
    /// Ölçüt pencerenin sidebar'ı TAŞIYIP taşıyamadığı: sidebar açıkken alt sınır
    /// sidebar kadar yükseliyor (bkz. `WindowLayout.minWidth(withAIPanel:withSidebar:)`),
    /// o sınırın altında sidebar'ın yeri yok.
    static func shouldCloseSidebar(availableWidth: Double) -> Bool {
        availableWidth < Double(WindowLayout.minWidth(withAIPanel: false, withSidebar: true))
    }

    // briefs/3 ikinci adım (*Sekme başlıkları kısaltılmalı*) burada DEĞİL: sekme
    // çubuğu bunu zaten kendi genişliğine göre yapıyor (`TabBarLayout.isCompact` +
    // SwiftUI `truncationMode`). İkinci bir kısaltma yolu yazmak, aynı kararı iki
    // yerde bakımı gereken iki kopyaya bölerdi.
}
