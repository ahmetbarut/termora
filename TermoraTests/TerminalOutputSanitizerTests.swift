import Foundation
import Testing
@testable import Termora

/// Komut bloklarının "Komutun çıktısı" alanını besleyen süzgeç (briefs/2).
///
/// Buradaki her testin ortak derdi: bloğa yazılan metin, kullanıcının terminalde GÖRDÜĞÜ
/// metin olmalı. Ne bir kaçış dizisi çöpü, ne yarım kalmış bir karakter, ne de aynı
/// ilerleme çubuğunun yüz kopyası.
@Suite("Terminal output sanitizer")
struct TerminalOutputSanitizerTests {

    private func sanitized(_ chunks: [String], maxCharacters: Int = 64_000) -> String {
        var sanitizer = TerminalOutputSanitizer(maxCharacters: maxCharacters)
        for chunk in chunks { sanitizer.consume(text: chunk) }
        return sanitizer.text
    }

    // MARK: - Kaçış dizileri

    /// Renk dizileri metnin PARÇASI DEĞİLDİR. Ham hâlde saklansaydı her `ls` çıktısı
    /// `[0m[01;34m` çöpüyle dolar, kopyalanan çıktı da yapıştırıldığı yerde bozuk olurdu.
    @Test func colourSequencesAreRemovedButTheirTextStays() {
        #expect(sanitized(["\u{1B}[0;32mok\u{1B}[0m"]) == "ok")
        #expect(sanitized(["\u{1B}[1;31merror:\u{1B}[0m missing file"]) == "error: missing file")
    }

    /// İmleç hareketleri ve ekran temizleme de düşer.
    @Test func cursorAndScreenControlSequencesAreRemoved() {
        #expect(sanitized(["a\u{1B}[2J\u{1B}[Hb"]) == "ab")
        #expect(sanitized(["x\u{1B}[10;20Hy"]) == "xy")
    }

    /// OSC dizileri (pencere başlığı, çalışma dizini) ve BİZİM OSC 133 işaretlerimiz
    /// çıktıya karışmaz — kullanıcı kendi komut sınırlarını metin olarak okumamalı.
    @Test func osc133MarkersAndWindowTitlesNeverReachTheBlockText() {
        let raw = "\u{1B}]0;my title\u{07}hello\u{1B}]133;D;0\u{07}"

        #expect(sanitized([raw]) == "hello")
    }

    /// OSC dizisi BEL yerine ST (`ESC \`) ile de bitebilir; iki bitiş de tanınmalı,
    /// yoksa süzgeç dizinin bittiğini göremez ve GERİ KALAN TÜM ÇIKTIYI yutardı.
    @Test func anOSCTerminatedByStringTerminatorAlsoEnds() {
        #expect(sanitized(["\u{1B}]7;file:///tmp\u{1B}\\after"]) == "after")
    }

    /// Karakter kümesi atamaları (`ESC ( B`) TAM İKİ bayttır. Yanlış sayılırsa sonraki
    /// harf yutulur ya da `B` metne sızardı.
    @Test func charsetDesignationsConsumeExactlyOneMoreByte() {
        #expect(sanitized(["\u{1B}(Bplain"]) == "plain")
    }

    /// Kaçış dizisi İKİ OKUMAYA bölünebilir — 4 KB'lik PTY okumasının nereye denk
    /// geleceğini kimse seçmiyor. Bölünmüş dizi metne sızmamalı.
    @Test func anEscapeSequenceSplitAcrossTwoReadsIsStillRemoved() {
        #expect(sanitized(["red:\u{1B}[", "31mvalue\u{1B}[0m"]) == "red:value")
        #expect(sanitized(["\u{1B}", "[1mbold"]) == "bold")
    }

    // MARK: - Satır sonları

    /// PTY satır sonlarını `\r\n` yollar; blok metninde `\n` beklenir, yoksa kopyalanan
    /// çıktı yapıştırıldığı yerde çift satır atlardı.
    @Test func carriageReturnLineFeedBecomesASingleNewline() {
        #expect(sanitized(["one\r\ntwo\r\n"]) == "one\ntwo\n")
    }

    /// İlerleme çubukları aynı satırı `\r` ile defalarca yeniden yazar. Ham hâlde tek bir
    /// indirme yüzlerce satıra dönüşürdü; kullanıcının GÖRDÜĞÜ son hâl kalmalı.
    @Test func aProgressBarCollapsesToWhatTheUserActuallySees() {
        #expect(sanitized(["10%\r50%\r100%\r\ndone\r\n"]) == "100%\ndone\n")
    }

    /// Backspace de ekranda gördüğünü siler.
    @Test func backspaceRemovesThePreviousCharacter() {
        #expect(sanitized(["abcX\u{08}"]) == "abc")
        // Satır başındaki backspace silecek bir şey bulamaz ve önceki satıra taşmaz.
        #expect(sanitized(["a\r\n\u{08}b"]) == "a\nb")
    }

    /// Sekme KORUNUR: hizalanmış çıktının (örneğin `git status`) anlamı ona bağlı.
    /// Diğer C0 kontrolleri (BEL gibi) metinde görünmez.
    @Test func tabsSurviveAndOtherControlCharactersDoNot() {
        #expect(sanitized(["a\tb\u{07}c"]) == "a\tbc")
    }

    // MARK: - UTF-8

    /// Çok baytlı bir karakter iki okumaya bölünebilir. Yarısı atılsaydı Türkçe, emoji ve
    /// kutu çizgileri içeren her çıktı bozuk görünürdü.
    @Test func aMultiByteCharacterSplitAcrossTwoReadsIsReassembled() {
        let bytes = Array("çalışıyor 🚀".utf8)
        var sanitizer = TerminalOutputSanitizer(maxCharacters: 64_000)
        // Tam ortadan böl: bir karakterin ortasına denk gelmesi neredeyse kesin.
        sanitizer.consume(bytes[..<(bytes.count / 2)])
        sanitizer.consume(bytes[(bytes.count / 2)...])

        #expect(sanitizer.text == "çalışıyor 🚀")
    }

    /// Geçersiz bayt SESSİZCE YUTULMAZ: çıktının bir parçasının kaybolduğunu gizlemek,
    /// kullanıcıyı eksik bir metne tam sanarak baktırırdı. Unicode'un cevabı U+FFFD'dir.
    @Test func invalidBytesBecomeAReplacementCharacterInsteadOfVanishing() {
        var sanitizer = TerminalOutputSanitizer(maxCharacters: 64_000)
        sanitizer.consume([0x61, 0xFF, 0xFE, 0x62] as [UInt8])

        #expect(sanitizer.text.contains("a"))
        #expect(sanitizer.text.contains("b"))
        #expect(sanitizer.text.contains("\u{FFFD}"))
    }

    // MARK: - Sınır

    /// `yes` ya da dev bir build günlüğü sınırsız büyüseydi tek sekme uygulamayı şişirirdi.
    /// Sınıra dayanınca BAŞ atılır, SON tutulur: bir komutun neden başarısız olduğu
    /// neredeyse her zaman son satırlardadır.
    @Test func anEndlessOutputKeepsItsTailAndAdmitsThatTheHeadIsGone() {
        var sanitizer = TerminalOutputSanitizer(maxCharacters: 40)
        for index in 1...100 { sanitizer.consume(text: "line \(index)\r\n") }

        #expect(sanitizer.didTruncate)
        #expect(sanitizer.text.count <= 40 + "line 100\n".count)
        #expect(sanitizer.text.contains("line 100"))
        #expect(!sanitizer.text.contains("line 1\n"))
    }

    /// Satır sonu HİÇ görmeyen dev bir çıktı (ör. tek satırlık bir JSON dökümü) sınırın
    /// kaçış yolu olamaz.
    @Test func aSingleEndlessLineIsAlsoBounded() {
        var sanitizer = TerminalOutputSanitizer(maxCharacters: 20)
        sanitizer.consume(text: String(repeating: "x", count: 500))

        #expect(sanitizer.didTruncate)
        #expect(sanitizer.text.count == 20)
    }

    /// Sınıra dayanmayan sıradan bir çıktı kırpılmadığını söyler; her bloğa "eksik"
    /// damgası vurmak uyarıyı anlamsızlaştırırdı.
    @Test func ordinaryOutputIsNotFlaggedAsTruncated() {
        var sanitizer = TerminalOutputSanitizer(maxCharacters: 64_000)
        sanitizer.consume(text: "hello\r\n")

        #expect(!sanitizer.didTruncate)
        #expect(!sanitizer.isEmpty)
    }

    @Test func aSanitizerThatSawNothingIsEmpty() {
        var sanitizer = TerminalOutputSanitizer(maxCharacters: 64_000)
        #expect(sanitizer.isEmpty)
        #expect(sanitizer.text.isEmpty)
        // Yalnız kaçış dizisi gören bir süzgeç de boştur.
        sanitizer.consume(text: "\u{1B}[0m")
        #expect(sanitizer.isEmpty)
    }
}
