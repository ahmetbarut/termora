import Foundation
import Testing
@testable import Termora

/// Komut bloklarının SIRALAMA garantisi.
///
/// # Bu tip neden var
///
/// SwiftTerm'ün `registerOscHandler` kancası ayrıştırma sırasında ateşlenir, ama Termora
/// ham baytları `dataReceived` üzerinden TEK PARÇA hâlinde alır ve oturum durumu
/// MainActor'a ait olduğu için kanca bir `Task` içinde ertelenir. Yani "şu bayt hangi
/// komutun çıktısı?" sorusuna SwiftTerm'ün kancasıyla cevap verilemez: 4 KB'lik tek bir
/// okuma `C`, çıktı ve `D`'yi birlikte taşıyabilir ve işaretler baytlardan SONRA gelir.
///
/// Bu tarayıcı sırayı KURULUŞ GEREĞİ korur: baytları kendisi yürür, işaretleri tam
/// bulundukları yerde üretir.
@Suite("Terminal stream scanner")
struct TerminalStreamScannerTests {

    /// Bir metin olayı TEK karakter taşır. Birleştirmek verimli görünür ama tüketici
    /// (`TerminalOutputSanitizer`) backspace ve `\r`'yi karakter karakter uygulamak
    /// zorunda: birleşik bir parçayı yine bölerdi, üstelik silme bir parçanın ortasına
    /// düştüğünde parçayı yeniden kurmak gerekirdi.
    private func events(_ chunks: [String]) -> [TerminalStreamEvent] {
        var scanner = TerminalStreamScanner()
        return chunks.flatMap { scanner.scan(Array($0.utf8)) }
    }

    private func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Tek bir okumada gelen "komut başladı → çıktı → komut bitti" üçlüsü, TAM O SIRAYLA
    /// çıkmalı. Çıktı yanlış tarafa düşseydi bir komutun çıktısı bir öncekinin bloğunda
    /// görünürdü — kullanıcının okuduğu her blok yalan olurdu.
    @Test func markersAndOutputComeOutInTheOrderTheyAppearedInTheStream() {
        let stream = "\u{1B}]133;C;cmd=\(base64("echo hi"))\u{07}hi\r\n\u{1B}]133;D;0\u{07}"

        #expect(events([stream]) == [
            .marker(.outputStart(command: "echo hi", directory: nil)),
            .text("h"), .text("i"),
            .carriageReturn,
            .newline,
            .marker(.commandEnd(exitCode: 0)),
        ])
    }

    /// Bir OSC dizisi iki okumaya bölünebilir — hem de tam base64'ün ortasından. Yarısı
    /// kaybolursa komut metni bulunamaz ve ekrana çöp basılırdı.
    @Test func anOSCSequenceSplitAcrossReadsIsStillRecognised() {
        let encoded = base64("git status")
        let first = "\u{1B}]133;C;cmd=" + encoded.prefix(4)
        let second = encoded.dropFirst(4) + "\u{07}ok"

        #expect(events([first, String(second)]) == [
            .marker(.outputStart(command: "git status", directory: nil)),
            .text("o"), .text("k"),
        ])
    }

    /// OSC 133 DIŞINDAKİ diziler (pencere başlığı, çalışma dizini bildirimi) işaret
    /// üretmez ve metne de sızmaz.
    @Test func unrelatedOSCSequencesProduceNeitherAMarkerNorText() {
        #expect(events(["\u{1B}]0;title\u{07}a\u{1B}]7;file:///tmp\u{1B}\\b"]) == [
            .text("a"), .text("b"),
        ])
    }

    /// Renk ve imleç dizileri metin akışından düşer; aralarındaki yazı kalır.
    @Test func csiSequencesAreStrippedFromTheTextEvents() {
        #expect(events(["\u{1B}[31mred\u{1B}[0m"]) == [.text("r"), .text("e"), .text("d")])
    }

    /// Satır sonu ve satır başı AYRI olaylardır: `\r\n`'i tek bir "satır bitti"ye
    /// indirmek, ilerleme çubuğunu yeniden yazan `\r`'yi de yutardı.
    @Test func carriageReturnAndNewlineAreSeparateEvents() {
        #expect(events(["a\r\nb\rc"]) == [
            .text("a"), .carriageReturn, .newline, .text("b"), .carriageReturn, .text("c"),
        ])
    }

    @Test func backspaceIsItsOwnEvent() {
        #expect(events(["ab\u{08}"]) == [.text("a"), .text("b"), .backspace])
    }

    /// Çok baytlı bir karakter iki okumaya bölünse de tek parça hâlinde çıkar.
    @Test func aMultiByteCharacterSplitAcrossReadsIsReassembled() {
        let bytes = Array("ş".utf8)
        var scanner = TerminalStreamScanner()
        let first = scanner.scan(bytes[..<1])
        let second = scanner.scan(bytes[1...])

        #expect(first.isEmpty)
        #expect(second == [.text("ş")])
    }

    /// Bitmeyen bir OSC dizisi (bozuk çıktı, ikili dosya `cat`'lenmesi) belleği sınırsız
    /// büyütemez. Yük sınıra dayarsa BIRAKILIR; tarayıcı diziyi izlemeye devam eder ve
    /// bittiğinde metne geri döner — akışın geri kalanını yutup terminali dilsiz bırakmaz.
    @Test func anUnterminatedOSCPayloadCannotGrowWithoutBound() {
        var scanner = TerminalStreamScanner()
        _ = scanner.scan(Array("\u{1B}]133;C;cmd=".utf8))
        for _ in 0..<200 {
            _ = scanner.scan(Array(String(repeating: "A", count: 1000).utf8))
        }
        let after = scanner.scan(Array("\u{07}back".utf8))

        #expect(after == [.text("b"), .text("a"), .text("c"), .text("k")])
    }

    /// BEL yerine ST (`ESC \`) ile biten OSC de tanınır; tanınmasaydı tarayıcı dizinin
    /// bittiğini göremez ve o noktadan sonraki HER ŞEYİ yutardı.
    @Test func anOSCTerminatedByStringTerminatorIsRecognised() {
        let stream = "\u{1B}]133;D;3\u{1B}\\done"

        #expect(events([stream]) == [
            .marker(.commandEnd(exitCode: 3)),
            .text("d"), .text("o"), .text("n"), .text("e"),
        ])
    }
}
