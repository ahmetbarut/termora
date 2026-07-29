import Foundation

/// PTY akışını komut bloklarına çeviren SAF kaydedici (briefs/2 "Komut Blokları").
///
/// Baytları `TerminalStreamScanner`'a verir, işaretlerden blok sınırlarını okur, aradaki
/// metni açık bloğun arındırıcısına yazar. Saat dışarıdan gelir: süre ölçen bir tipi
/// gerçek zamana bağlamak testi de zamana bağlardı.
///
/// # Ne zaman blok YOKTUR
///
/// Shell integration kurulu değilse OSC 133 işareti hiç gelmez ve kaydedici blok
/// üretmez. Komut adı bilinmeyen bir "blok" uydurmak, kullanıcıya sahte yapı
/// göstermek olurdu — çıktı zaten terminalin kendi tamponunda duruyor.
struct CommandBlockRecorder {

    /// Tamamlanmış ve çalışan bloklar, eskiden yeniye.
    private(set) var blocks: [CommandBlock] = []

    private var scanner = TerminalStreamScanner()

    /// Açık bloğun çıktısını biriktiren süzgeç. Blok kapanınca atılır.
    private var sanitizer: TerminalOutputSanitizer?

    private let maxBlocks: Int

    init(maxBlocks: Int = CommandBlockLimits.maxBlocks) {
        self.maxBlocks = maxBlocks
    }

    mutating func consume(_ bytes: some Sequence<UInt8>, now: Date) {
        for event in scanner.scan(bytes) {
            switch event {
            case let .marker(.outputStart(command, directory)):
                // Kabuk `D` yaymadan yeni komut başlayabilir (kanca yarım kurulu,
                // kullanıcı Ctrl-C'ledi). Sonsuza kadar "Running" gösteren bir blok
                // yalandır; öncekini çıkış kodu OLMADAN kapatırız.
                closeOpenBlock(exitCode: nil, at: now)
                openBlock(command: command, directory: directory, at: now)

            case let .marker(.commandEnd(exitCode)):
                closeOpenBlock(exitCode: exitCode, at: now)

            case .marker(.promptStart), .marker(.commandStart):
                // Bunlar istemi ve girdiyi işaretler; blok sınırı değildir.
                continue

            default:
                guard sanitizer != nil else { continue }
                sanitizer?.consume(events: [event])
                flushOutputToOpenBlock()
            }
        }
    }

    mutating func clear() {
        blocks.removeAll()
        sanitizer = nil
    }

    // MARK: - Blok yaşam döngüsü

    private mutating func openBlock(command: String?, directory: String?, at date: Date) {
        blocks.append(CommandBlock(command: command,
                                   startedAt: date,
                                   workingDirectory: directory))
        sanitizer = TerminalOutputSanitizer()
        enforceBlockLimit()
    }

    /// `exitCode` nil ise blok `.finished` olur — 0 varsaymak başarısız bir komutu
    /// başarılı göstermek olurdu (bkz. `CommandBlockState`).
    private mutating func closeOpenBlock(exitCode: Int?, at date: Date) {
        guard sanitizer != nil, let index = blocks.indices.last, blocks[index].isRunning else {
            sanitizer = nil
            return
        }
        blocks[index].finishedAt = date
        blocks[index].exitCode = exitCode
        sanitizer = nil
    }

    /// Çıktı her olayda bloğa yazılır, blok kapanınca değil: çalışan bir komutun çıktısı
    /// akarken görünmeli (briefs/2 "devam ediyor" durumu).
    private mutating func flushOutputToOpenBlock() {
        guard let sanitizer, let index = blocks.indices.last, blocks[index].isRunning else {
            return
        }
        blocks[index].output = Self.trimmingFinalNewline(sanitizer.text)
        blocks[index].didTruncateOutput = sanitizer.didTruncate
    }

    /// Kabuk çıktısı hemen her zaman `\n` ile biter. Onu olduğu gibi bırakmak her bloğun
    /// altına boş bir satır koyardı. YALNIZ sonuncusu atılır: art arda iki satırbaşıyla
    /// biten bir çıktıda kullanıcının gerçekten yazdırdığı boş satır korunur.
    private static func trimmingFinalNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// En ESKİ blok düşer. Sınırsız büyüme uzun bir oturumda belleği şişirirdi
    /// (briefs/1 "Performans Gereksinimleri").
    private mutating func enforceBlockLimit() {
        guard blocks.count > maxBlocks else { return }
        blocks.removeFirst(blocks.count - maxBlocks)
    }
}
