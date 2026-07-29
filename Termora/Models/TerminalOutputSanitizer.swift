import Foundation

// MARK: - Sınırlar

/// Komut bloklarının bellek bütçesi.
///
/// Bloklar terminalin scrollback'inin YERİNE GEÇMEZ; onun yanında duran bir inceleme
/// yüzeyidir. Gerçek geçmiş SwiftTerm'ün tamponunda, kullanıcının ayarladığı satır
/// sayısıyla durur. Bu yüzden buradaki sınırlar cömert değil, dar tutuldu: `yes` ya da
/// bir `docker build` çıktısı sınırsız büyüseydi tek bir sekme uygulamayı şişirirdi.
enum CommandBlockLimits {
    /// Blok başına saklanan en fazla karakter. Aşıldığında BAŞ atılır, SON tutulur.
    ///
    /// Sonu tutmak bilinçli: bir komutun neden başarısız olduğu neredeyse her zaman son
    /// satırlarda yazar. Baş taraf kaybolduğunda blok bunu `didTruncateOutput` ile SÖYLER —
    /// sessizce kırpmak, kullanıcıyı eksik bir çıktıya tam sanarak baktırırdı.
    nonisolated static let maxOutputCharacters = 64_000

    /// Oturum başına saklanan en fazla blok. Aşıldığında en ESKİ blok düşer.
    nonisolated static let maxBlocks = 100
}

// MARK: - Arındırıcı

/// PTY'den gelen ham baytları okunabilir düz metne çeviren ARTIMLI süzgeç.
///
/// # Neden artımlı
///
/// Bir kaçış dizisi ya da çok baytlı bir UTF-8 karakteri iki ayrı `dataReceived` çağrısına
/// BÖLÜNEBİLİR — 4 KB'lik okuma sınırının nereye denk geleceğini kimse seçmiyor. Tek
/// seferlik saf bir fonksiyon, sınıra denk gelen her dizinin yarısını ekrana metin diye
/// basardı (`[0m` gibi çöp) ve her Türkçe karakteri ikiye bölerdi.
///
/// # Ne ATILIR
///
/// CSI (`ESC [ … `), OSC (`ESC ] … BEL/ST`), DCS/SOS/PM/APC ve tek karakterlik kaçışlar.
/// Bunlar rengi, imleci ve pencere başlığını yönetir; blok metninde karşılığı yoktur.
/// OSC 133 işaretleri de buradan düşer — kullanıcı kendi komut sınırlarını okumamalı.
///
/// # `\r` neden satırı SİLER
///
/// İlerleme çubukları (`npm`, `pip`, `curl`) aynı satırı `\r` ile defalarca yeniden yazar.
/// Ham hâlde saklanınca tek bir indirme yüzlerce satıra dönüşürdü; `\r`'yi "bu satıra
/// baştan başla" diye okumak kullanıcının ekranda GÖRDÜĞÜ son hâli bırakır.
struct TerminalOutputSanitizer {

    private enum Mode {
        case text
        /// `ESC` görüldü, türü henüz bilinmiyor.
        case escape
        /// `ESC [` — final bayta (0x40–0x7E) kadar yutulur.
        case csi
        /// `ESC ]` — BEL ya da ST (`ESC \`) gelene kadar yutulur.
        case osc
        /// OSC içindeyken `ESC` görüldü; `\` gelirse dizi biter.
        case oscEscape
        /// DCS/SOS/PM/APC — hepsi ST ile biter.
        case string
        case stringEscape
        /// `ESC ( B` gibi karakter kümesi atamaları: tam olarak bir bayt daha yutulur.
        case charset
    }

    private let maxCharacters: Int
    private var mode: Mode = .text
    /// Tamamlanmamış UTF-8 dizisi; sonraki parçada tamamlanır.
    private var pendingUTF8: [UInt8] = []
    private var expectedUTF8Count = 0

    /// Biten satırlar ve üzerinde çalışılan satır ayrı tutulur; `\r` yalnız sonuncuyu siler.
    private var lines: [String] = []
    private var current: String = ""
    private var characterCount = 0

    /// `\r` görüldü ama etkisi HENÜZ uygulanmadı.
    ///
    /// PTY satır sonunu `\r\n` yollar. `\r` anında "satırı sil" diye uygulansaydı her
    /// satır, tam da bittiği anda silinir ve blok bomboş kalırdı — gerçek bir hata olarak
    /// yakalandı. Silme yalnız `\r`'den sonra BAŞKA bir karakter gelirse anlamlıdır; o
    /// zaman gerçekten aynı satırın üzerine yazılıyordur (ilerleme çubuğu).
    private var hasPendingCarriageReturn = false

    /// Sınır yüzünden çıktının BAŞI atıldı mı.
    private(set) var didTruncate = false

    init(maxCharacters: Int) {
        self.maxCharacters = maxCharacters
    }

    /// Varsayılan sınırla. `init(maxCharacters:)`'ın varsayılan argümanı YOK: varsayılan
    /// argüman ifadeleri yalıtımsız bağlamda değerlendirilir ve bu projede tam olarak bu
    /// tuzağa altı kez düşülmüş.
    init() {
        self.init(maxCharacters: CommandBlockLimits.maxOutputCharacters)
    }

    /// Şu ana kadar toplanan düz metin.
    var text: String {
        current.isEmpty && lines.isEmpty ? "" : (lines + [current]).joined(separator: "\n")
    }

    var isEmpty: Bool { lines.isEmpty && current.isEmpty }

    mutating func consume(_ bytes: some Sequence<UInt8>) {
        for byte in bytes { consume(byte: byte) }
    }

    /// Test ve dikiş kolaylığı; metni UTF-8'e çevirip aynı yoldan geçirir.
    mutating func consume(text: String) {
        consume(Array(text.utf8))
    }

    private mutating func consume(byte: UInt8) {
        switch mode {
        case .escape:
            enterMode(after: byte)
            return
        case .csi:
            // Final bayt aralığı 0x40–0x7E; öncesindekiler parametre ve ara baytlardır.
            if (0x40...0x7E).contains(byte) { mode = .text }
            return
        case .osc, .string:
            if byte == 0x07 { mode = .text } // BEL
            else if byte == 0x1B { mode = (mode == .osc) ? .oscEscape : .stringEscape }
            return
        case .oscEscape, .stringEscape:
            // `ESC \` (ST) diziyi bitirir; başka bir şeyse dizi sürüyordur.
            mode = (byte == 0x5C) ? .text : (mode == .oscEscape ? .osc : .string)
            return
        case .charset:
            mode = .text
            return
        case .text:
            break
        }

        if byte == 0x1B {
            flushPendingUTF8()
            mode = .escape
            return
        }
        if byte >= 0x80 {
            consumeUTF8(byte: byte)
            return
        }
        flushPendingUTF8()
        consumeASCII(byte: byte)
    }

    private mutating func enterMode(after byte: UInt8) {
        switch byte {
        case 0x5B: mode = .csi                      // [
        case 0x5D: mode = .osc                      // ]
        case 0x50, 0x58, 0x5E, 0x5F: mode = .string // P (DCS), X (SOS), ^ (PM), _ (APC)
        case 0x28, 0x29, 0x2A, 0x2B: mode = .charset // ( ) * +
        default: mode = .text                        // ESC 7, ESC =, … tek karakterlik
        }
    }

    // MARK: UTF-8

    private mutating func consumeUTF8(byte: UInt8) {
        if byte >= 0xC0 {
            // Yeni bir öncü bayt: yarım kalmış dizi bozuktur, olduğu gibi çözülüp atılır.
            flushPendingUTF8()
            pendingUTF8 = [byte]
            expectedUTF8Count = byte >= 0xF0 ? 4 : (byte >= 0xE0 ? 3 : 2)
        } else if pendingUTF8.isEmpty {
            // Öncüsü olmayan devam baytı: tek başına anlamsız, atılır.
            return
        } else {
            pendingUTF8.append(byte)
        }
        if pendingUTF8.count >= expectedUTF8Count { flushPendingUTF8() }
    }

    /// Biriken baytları çözer. Geçersiz dizi U+FFFD olur — sessizce yutmak, çıktının bir
    /// parçasının kaybolduğunu gizlerdi.
    private mutating func flushPendingUTF8() {
        guard !pendingUTF8.isEmpty else { return }
        let decoded = String(decoding: pendingUTF8, as: UTF8.self)
        pendingUTF8.removeAll(keepingCapacity: true)
        expectedUTF8Count = 0
        for character in decoded { appendCharacter(character) }
    }

    // MARK: ASCII

    private mutating func consumeASCII(byte: UInt8) {
        switch byte {
        case 0x0A: // \n — `\r\n` ise bekleyen silme HÜKÜMSÜZDÜR, satır olduğu gibi kapanır
            hasPendingCarriageReturn = false
            lines.append(current)
            current = ""
            characterCount += 1
            enforceLimit()
        case 0x0D: // \r — etkisi bir sonraki karakteri görünce uygulanır
            hasPendingCarriageReturn = true
        case 0x08: // \b
            applyPendingCarriageReturn()
            if !current.isEmpty {
                current.removeLast()
                characterCount -= 1
            }
        case 0x09: // \t korunur
            appendCharacter("\t")
        default:
            // Diğer C0 kontrol karakterleri (BEL, SO, SI…) ve DEL metinde görünmez.
            guard byte >= 0x20, byte != 0x7F else { return }
            appendCharacter(Character(UnicodeScalar(byte)))
        }
    }

    /// Bekleyen `\r`: gerçekten aynı satırın üzerine yazılıyor, satır baştan başlar.
    private mutating func applyPendingCarriageReturn() {
        guard hasPendingCarriageReturn else { return }
        hasPendingCarriageReturn = false
        characterCount -= current.count
        current = ""
    }

    private mutating func appendCharacter(_ character: Character) {
        applyPendingCarriageReturn()
        current.append(character)
        characterCount += 1
        enforceLimit()
    }

    /// Sınır aşıldığında EN ESKİ satırlar düşer.
    private mutating func enforceLimit() {
        while characterCount > maxCharacters, !lines.isEmpty {
            characterCount -= lines.removeFirst().count + 1
            didTruncate = true
        }
        // Tek bir satır bile sınırı aşıyorsa (satır sonu görmemiş dev bir çıktı) onun da
        // başı atılır; yoksa sınırın hiç tutmadığı bir kaçış yolu kalırdı.
        if characterCount > maxCharacters, lines.isEmpty {
            let excess = characterCount - maxCharacters
            current.removeFirst(min(excess, current.count))
            characterCount = current.count
            didTruncate = true
        }
    }
}
