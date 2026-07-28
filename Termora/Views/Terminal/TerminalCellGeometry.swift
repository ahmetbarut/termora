import CoreGraphics
import Foundation

/// İmlecin altındaki terminal hücresini bulan SAF katman (briefs/3 "Sağ Tık Menüleri" ▸
/// Open Link / Copy Link).
///
/// # Neden burada
///
/// SwiftTerm bu dönüşümü `calculateMouseHit` içinde zaten yapıyor ama o `internal`; başka
/// bir modülden çağrılamıyor. Formül `computeFontDimensions` + `calculateMouseHit`
/// kodundan birebir alındı.
///
/// # Çoğaltmanın riski ve kapağı
///
/// Çoğaltılan bir formül sessizce ayrışabilir. Bu yüzden çağıran taraf `agrees(...)` ile
/// hesabı SwiftTerm'ün KENDİ bildirdiği hücre boyutuna karşı doğrular; uyuşmazsa bağlantı
/// öğeleri açılmaz. Yanlış bir URL açmaktansa hiç açmamak doğrudur.
enum TerminalCellGeometry {

    /// Tek bir hücrenin punto cinsinden boyutu.
    ///
    /// SwiftTerm: yükseklik `ceil((ascent + descent + leading) * lineSpacing)`, genişlik
    /// `"W"` glifinin ilerlemesi. Ölçülemeyen font (0 ya da negatif) hücre ÜRETMEZ:
    /// üretseydi her tıklama 0. sütuna düşer ve satır başındaki bağlantı her yerde
    /// "bulunmuş" olurdu.
    static func cellSize(ascent: CGFloat,
                         descent: CGFloat,
                         leading: CGFloat,
                         advanceWidth: CGFloat,
                         lineSpacing: CGFloat) -> CGSize? {
        let height = ceil((ascent + descent + leading) * lineSpacing)
        guard advanceWidth > 0, height > 0 else { return nil }
        return CGSize(width: advanceWidth, height: height)
    }

    /// Görünüm koordinatındaki bir noktayı GÖRÜNÜR alanın satır/sütununa çevirir.
    ///
    /// `point` AppKit koordinatındadır (y aşağıdan yukarı), terminal satırları yukarıdan
    /// aşağı sayılır; ters çevirme unutulursa tıklama ekranın dikey aynasına düşer.
    ///
    /// Sonuç GÖRÜNTÜ satırıdır (kaydırma ofseti eklenmemiştir); SwiftTerm'e `.screen(...)`
    /// olarak verilir ve ofseti o ekler.
    ///
    /// Terminal görünümün tamamını doldurmaz (sağda ve altta artık kalır); artığa yapılan
    /// tıklama son hücreye sıkıştırılır, yoksa var olmayan bir satır sorulurdu.
    static func cell(at point: CGPoint,
                     viewHeight: CGFloat,
                     cellSize: CGSize,
                     cols: Int,
                     rows: Int) -> (col: Int, row: Int)? {
        guard cellSize.width > 0, cellSize.height > 0, cols > 0, rows > 0, viewHeight > 0 else {
            return nil
        }
        let rawColumn = Int((point.x / cellSize.width).rounded(.down))
        let rawRow = Int(((viewHeight - point.y) / cellSize.height).rounded(.down))
        return (col: min(max(0, rawColumn), cols - 1),
                row: min(max(0, rawRow), rows - 1))
    }

    /// Hesabımız SwiftTerm'ün kendi bildirdiği piksel boyutuyla uyuşuyor mu?
    ///
    /// SwiftTerm `round(hücre * ölçek)` bildiriyor; aynı yuvarlamayı uygulayıp
    /// karşılaştırıyoruz. Uyuşmazlık, formülün ayrıştığı anlamına gelir.
    static func agrees(cellSize: CGSize,
                       withPixelSize pixelSize: (width: Int, height: Int),
                       scale: CGFloat) -> Bool {
        Int((cellSize.width * scale).rounded()) == pixelSize.width
            && Int((cellSize.height * scale).rounded()) == pixelSize.height
    }
}
