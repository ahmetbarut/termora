import Foundation
import Testing
@testable import Termora

/// briefs/3 "Küçük Pencere Davranışı".
///
/// Brief beş adımlık bir daralma sırası veriyor ve sonuncusu şart: *Terminal alanı
/// korunmalı.* Sıra saf bir karar olarak tutuluyor — hangi bilginin önce düşeceği,
/// pencere çizilmeden sınanabilmeli.
@Suite("Küçük pencere davranışı")
struct CompactWindowTests {

    @Test func theMinimumWindowSizeIsTheOneTheBriefGives() {
        #expect(WindowLayout.minWidth == 720)
        #expect(WindowLayout.minHeight == 480)
    }

    /// Geniş pencerede hiçbir şey düşmez.
    @Test func nothingIsDroppedWhenThereIsRoom() {
        let level = CompactionLevel(availableWidth: 1400)
        #expect(level == .full)
        #expect(level.showsWorkingDirectory)
        #expect(level.showsGitDetail)
        #expect(level.showsTerminalSize)
    }

    /// briefs/3'ün ilk adımı: *Status bar bilgileri azaltılmalı.* Önce en az gereken
    /// düşer — terminal ölçüsü, kullanıcının en seyrek baktığı bilgidir.
    @Test func theFirstThingToGoIsTheLeastNeededStatusItem() {
        let level = CompactionLevel(availableWidth: 900)
        #expect(level == .reduced)
        #expect(level.showsTerminalSize == false)
        // Dizin ve git hâlâ duruyor: bunlar kullanıcının nerede olduğunu söyler.
        #expect(level.showsWorkingDirectory)
        #expect(level.showsGitDetail)
    }

    /// Daha da dar: git detayı düşer, dizin kalır. Nerede olduğunu bilmek, hangi dalda
    /// olduğunu bilmekten önce gelir.
    @Test func gitDetailGoesBeforeTheWorkingDirectory() {
        let level = CompactionLevel(availableWidth: 760)
        #expect(level == .minimal)
        #expect(level.showsGitDetail == false)
        #expect(level.showsWorkingDirectory)
    }

    /// Alt sınırda bile çalışma dizini kalır: kullanıcı hangi klasörde olduğunu
    /// göremezse durum çubuğu hiçbir işe yaramaz.
    @Test func theWorkingDirectorySurvivesEvenAtTheSmallestSize() {
        #expect(CompactionLevel(availableWidth: WindowLayout.minWidth).showsWorkingDirectory)
    }

    /// briefs/3'ün dördüncü adımı: *Sidebar otomatik kapanabilmeli.* "Kapanabilmeli" —
    /// yani pencere sidebar'ı taşıyamayacak kadar darsa.
    @Test func theSidebarStepsAsideWhenTheWindowCannotCarryIt() {
        // Sidebar açıkken pencerenin alt sınırı sidebar kadar yükselir; o sınırın
        // altında sidebar'ın yeri yoktur.
        let tooNarrow = Double(WindowLayout.minWidth) + 50
        #expect(CompactionLevel.shouldCloseSidebar(availableWidth: tooNarrow))

        let roomy = Double(WindowLayout.minWidth(withAIPanel: false, withSidebar: true)) + 50
        #expect(CompactionLevel.shouldCloseSidebar(availableWidth: roomy) == false)
    }

    /// briefs/3'ün ikinci adımı (*Sekme başlıkları kısaltılmalı*) sekme çubuğunun kendi
    /// işi ve `TabBarLayoutTests` orada ölçüyor. Burada tekrar ölçmek, aynı kararı iki
    /// yerde bakımı gereken iki teste bölerdi.
}
