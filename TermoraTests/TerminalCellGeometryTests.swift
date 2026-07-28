import CoreGraphics
import Foundation
import Testing
@testable import Termora

/// briefs/3 "Sağ Tık Menüleri" ▸ Open Link / Copy Link için gereken tek şey: imlecin
/// altındaki HÜCRE. SwiftTerm bu dönüşümü kendi içinde yapıyor ama `internal`; Termora
/// aynı formülü burada saf ve testli olarak tutar.
///
/// Formül SwiftTerm'ün `calculateMouseHit` / `computeFontDimensions` kodundan alınmıştır.
/// Çoğaltma riskini kapatan şey `TermoraTerminalView`'daki DOĞRULAMA adımıdır: hesap
/// SwiftTerm'ün kendi bildirdiği hücre boyutuyla uyuşmazsa bağlantı öğeleri açılmaz.
@Suite("Terminal hücre geometrisi")
struct TerminalCellGeometryTests {

    private let cell = CGSize(width: 10, height: 20)

    // MARK: - Hücre boyutu

    /// SwiftTerm: `cellHeight = ceil((ascent + descent + leading) * lineSpacing)`,
    /// `cellWidth = "W" glifinin ilerlemesi`.
    @Test func heightIsTheRoundedUpLineBoxTimesLineSpacing() throws {
        let size = try #require(TerminalCellGeometry.cellSize(ascent: 10.2, descent: 3.1, leading: 0.4,
                                                              advanceWidth: 7.5, lineSpacing: 1.0))
        #expect(size.height == 14)      // ceil(13.7)
        #expect(size.width == 7.5)
    }

    @Test func lineSpacingStretchesOnlyTheHeight() throws {
        let size = try #require(TerminalCellGeometry.cellSize(ascent: 10, descent: 4, leading: 0,
                                                              advanceWidth: 7.5, lineSpacing: 1.5))
        #expect(size.height == 21)      // ceil(14 * 1.5)
        #expect(size.width == 7.5)
    }

    /// Ölçülemeyen bir font (genişlik 0) hücre üretmez; üretseydi her tıklama 0. sütuna
    /// düşer ve satırın başındaki bağlantı her yerde "bulunmuş" olurdu.
    @Test func aFontThatMeasuresToNothingProducesNoCell() {
        #expect(TerminalCellGeometry.cellSize(ascent: 0, descent: 0, leading: 0, advanceWidth: 0,
                                              lineSpacing: 1) == nil)
        #expect(TerminalCellGeometry.cellSize(ascent: 10, descent: 4, leading: 0, advanceWidth: -1,
                                              lineSpacing: 1) == nil)
    }

    // MARK: - Nokta → hücre

    /// AppKit'te y AŞAĞIDAN yukarı artar, terminal satırları YUKARIDAN aşağı. Dönüşüm
    /// ters çevirmeyi unutursa tıklama ekranın dikey aynasına düşer.
    @Test func theTopLeftPixelIsTheFirstCell() throws {
        let hit = try #require(TerminalCellGeometry.cell(at: CGPoint(x: 0, y: 200),
                                                         viewHeight: 200, cellSize: cell,
                                                         cols: 80, rows: 10))
        #expect(hit.col == 0)
        #expect(hit.row == 0)
    }

    @Test func aPointInTheMiddleLandsOnItsOwnCell() throws {
        // x = 35 → 3. sütun (30..<40), y = 200-45 = 155 → 155/20 = 7. satır
        let hit = try #require(TerminalCellGeometry.cell(at: CGPoint(x: 35, y: 45),
                                                         viewHeight: 200, cellSize: cell,
                                                         cols: 80, rows: 10))
        #expect(hit.col == 3)
        #expect(hit.row == 7)
    }

    /// Terminal görünümün tamamını doldurmaz (sağda ve altta artık kalır). Artığa yapılan
    /// tıklama son hücreye SIKIŞTIRILIR; sıkıştırılmazsa var olmayan bir satır sorulur.
    @Test func aClickInTheLeftoverMarginIsClampedToTheLastCell() throws {
        let hit = try #require(TerminalCellGeometry.cell(at: CGPoint(x: 1_000, y: -5),
                                                         viewHeight: 200, cellSize: cell,
                                                         cols: 80, rows: 10))
        #expect(hit.col == 79)
        #expect(hit.row == 9)
    }

    @Test func aNegativeCoordinateIsClampedToTheFirstCell() throws {
        let hit = try #require(TerminalCellGeometry.cell(at: CGPoint(x: -40, y: 5_000),
                                                         viewHeight: 200, cellSize: cell,
                                                         cols: 80, rows: 10))
        #expect(hit.col == 0)
        #expect(hit.row == 0)
    }

    /// Henüz ölçülmemiş bir terminal (0 sütun) hücre üretmez.
    @Test func anUnsizedTerminalProducesNoCell() {
        #expect(TerminalCellGeometry.cell(at: .zero, viewHeight: 200, cellSize: cell,
                                          cols: 0, rows: 10) == nil)
        #expect(TerminalCellGeometry.cell(at: .zero, viewHeight: 200, cellSize: cell,
                                          cols: 80, rows: 0) == nil)
        #expect(TerminalCellGeometry.cell(at: .zero, viewHeight: 0, cellSize: cell,
                                          cols: 80, rows: 10) == nil)
    }

    // MARK: - SwiftTerm ile uyuşma kontrolü

    /// Hesabımız SwiftTerm'ün kendi bildirdiği piksel boyutuyla uyuşuyor mu? Uyuşmuyorsa
    /// (SwiftTerm formülü değiştirdi) bağlantı öğeleri AÇILMAZ — yanlış bir URL açmaktansa
    /// hiç açmamak doğrudur.
    @Test func agreementIsCheckedAgainstSwiftTermsOwnPixelSize() {
        // 2x ekranda 7.5 x 14 pt → 15 x 28 piksel.
        #expect(TerminalCellGeometry.agrees(cellSize: CGSize(width: 7.5, height: 14),
                                            withPixelSize: (width: 15, height: 28),
                                            scale: 2))
        #expect(!TerminalCellGeometry.agrees(cellSize: CGSize(width: 7.5, height: 14),
                                             withPixelSize: (width: 16, height: 28),
                                             scale: 2))
    }
}
