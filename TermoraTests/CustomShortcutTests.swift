import SwiftUI
import Testing
@testable import Termora

/// briefs/2 "Ayarlar Ekranı": *Klavye kısayolları çakıştığında kullanıcı uyarılmalıdır.*
///
/// Uyarı ancak kullanıcı bir kısayolu DEĞİŞTİREBİLİYORSA anlamlıdır; katalog sabitken
/// çakışma zaten bir test tarafından engelleniyor. Bu paket, kullanıcının atamalarının
/// kataloğa nasıl uygulandığını ve çakışmanın nasıl bulunduğunu ölçer.
@Suite("Özel klavye kısayolları")
struct CustomShortcutTests {

    private func stroke(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> String {
        AppShortcut(id: "probe", title: "Probe", key: key, modifiers: modifiers).stroke
    }

    @Test func withoutCustomAssignmentsTheCatalogIsUnchanged() {
        #expect(AppShortcuts.resolved(customStrokes: [:]).map(\.id) == AppShortcuts.all.map(\.id))
        #expect(AppShortcuts.resolved(customStrokes: [:]).map(\.stroke)
                == AppShortcuts.all.map(\.stroke))
    }

    /// Kullanıcının ataması kataloğun üstüne yazar. Kimlik KORUNUR: kayıt kimliğe
    /// bağlıdır, başlık çevrildiğinde ya da değiştiğinde atama kaybolmamalı.
    @Test func aCustomAssignmentReplacesTheDefaultStroke() {
        let custom = [AppShortcuts.newTab.id: stroke("n", [.command, .option])]

        let resolved = AppShortcuts.resolved(customStrokes: custom)
        let newTab = resolved.first { $0.id == AppShortcuts.newTab.id }

        #expect(newTab?.stroke == stroke("n", [.command, .option]))
        #expect(newTab?.title == AppShortcuts.newTab.title)
        #expect(resolved.count == AppShortcuts.all.count)
    }

    /// Tanınmayan bir vuruş dizesi (elle bozulmuş ayar dosyası) YOK SAYILIR ve komut
    /// varsayılanında kalır. Kısayolsuz bir menü öğesi, kullanıcının değiştirdiğini
    /// sandığı ama hiç çalışmayan bir komut demekti.
    @Test func anUnreadableStrokeFallsBackToTheDefault() {
        let resolved = AppShortcuts.resolved(customStrokes: [AppShortcuts.find.id: "garbage"])

        #expect(resolved.first { $0.id == AppShortcuts.find.id }?.stroke
                == AppShortcuts.find.stroke)
    }

    /// Bilinmeyen bir komut kimliği (kaldırılmış bir özellik) sessizce atlanır.
    @Test func anAssignmentForAnUnknownCommandIsIgnored() {
        let resolved = AppShortcuts.resolved(customStrokes: ["thereIsNoSuchCommand": stroke("z", .command)])

        #expect(resolved.count == AppShortcuts.all.count)
        #expect(resolved.map(\.stroke) == AppShortcuts.all.map(\.stroke))
    }

    /// Asıl mesele: kullanıcı bir kısayolu BAŞKA bir komutunkiyle aynı yaparsa çakışma
    /// GÖRÜNMELİ. Sessizce kabul etmek, iki komuttan birinin hiç çalışmaması demekti.
    @Test func assigningAStrokeThatIsAlreadyTakenIsReportedAsAConflict() {
        let custom = [AppShortcuts.newTab.id: AppShortcuts.find.stroke]

        let conflicts = AppShortcuts.conflicts(in: AppShortcuts.resolved(customStrokes: custom))
        let ids = Set(conflicts.flatMap { $0.map(\.id) })

        #expect(ids.contains(AppShortcuts.newTab.id))
        #expect(ids.contains(AppShortcuts.find.id))
    }

    /// Bir komutu kendi varsayılanına geri almak çakışma üretmez.
    @Test func restoringADefaultClearsTheConflict() {
        var custom = [AppShortcuts.newTab.id: AppShortcuts.find.stroke]
        #expect(AppShortcuts.conflicts(in: AppShortcuts.resolved(customStrokes: custom)).isEmpty == false)

        custom.removeValue(forKey: AppShortcuts.newTab.id)

        #expect(AppShortcuts.conflicts(in: AppShortcuts.resolved(customStrokes: custom)).isEmpty)
    }

    /// Vuruş dizesi ile tuş/değiştirici arasındaki dönüşüm KAYIPSIZ olmalı: ayar diske
    /// dize olarak yazılıyor ve geri okunduğunda aynı kısayolu vermeli.
    @Test func aStrokeSurvivesARoundTripThroughItsTextForm() {
        for shortcut in AppShortcuts.all {
            let parsed = AppShortcuts.shortcut(from: shortcut.stroke)
            #expect(parsed != nil, "çözülemedi: \(shortcut.id)")
            #expect(parsed.map { stroke($0.key, $0.modifiers) } == shortcut.stroke)
        }
    }

    @Test func settingsStartWithNoCustomAssignments() {
        #expect(AppSettings().customShortcutStrokes.isEmpty)
    }
}
