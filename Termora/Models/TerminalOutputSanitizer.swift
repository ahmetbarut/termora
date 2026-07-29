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

    private let maxCharacters: Int

    /// Kaçış dizilerini, UTF-8 birleştirmeyi ve OSC 133 işaretlerini AYIRAN taraf.
    ///
    /// Bu iş eskiden burada bir kez daha yazılıydı; iki kopya durum makinesi demekti ve
    /// birinde düzeltilen bir hata diğerinde yaşamaya devam ederdi. Arındırıcı artık
    /// tarayıcının ÜSTÜNDE duruyor ve yalnız "görünen metin ne oldu" sorusuyla ilgileniyor.
    private var scanner = TerminalStreamScanner()

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
        consume(events: scanner.scan(bytes))
    }

    /// Olayları doğrudan tüketir. Komut bloklarını kuran taraf (`CommandBlockRecorder`)
    /// tarayıcıyı zaten kendi yürütür ve baytları ikinci kez ayrıştırmamalıdır.
    ///
    /// `.marker` olayları YOK SAYILIR: kullanıcı kendi komut sınırlarını çıktı metninde
    /// okumamalı.
    mutating func consume(events: [TerminalStreamEvent]) {
        for event in events {
            switch event {
            case let .text(text):
                for character in text { appendCharacter(character) }
            case .newline:
                // `\r\n` ise bekleyen silme HÜKÜMSÜZDÜR, satır olduğu gibi kapanır.
                hasPendingCarriageReturn = false
                lines.append(current)
                current = ""
                characterCount += 1
                enforceLimit()
            case .carriageReturn:
                // Etkisi bir sonraki karakteri görünce uygulanır (bkz. alan yorumu).
                hasPendingCarriageReturn = true
            case .backspace:
                applyPendingCarriageReturn()
                if !current.isEmpty {
                    current.removeLast()
                    characterCount -= 1
                }
            case .marker:
                continue
            }
        }
    }

    /// Test ve dikiş kolaylığı; metni UTF-8'e çevirip aynı yoldan geçirir.
    mutating func consume(text: String) {
        consume(Array(text.utf8))
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
