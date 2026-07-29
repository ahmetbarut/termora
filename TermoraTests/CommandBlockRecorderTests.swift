import Foundation
import Testing
@testable import Termora

/// briefs/2 "Komut Blokları": komut, çıktısı, süresi, çıkış kodu ve durumu.
///
/// Kaydedici saf: baytları alır, blok listesi verir. Saat dışarıdan enjekte edilir —
/// süre ölçen bir tipi gerçek zamana bağlamak, testi de zamana bağlar.
@Suite("Komut bloğu kaydedici")
struct CommandBlockRecorderTests {

    private func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    private func start(_ command: String, directory: String? = nil) -> String {
        var payload = "\u{1B}]133;C;cmd=\(base64(command))"
        // Alan adı `pwd`: kabuk kancasının gerçekte yaydığı ad bu
        // (`ShellIntegration.outputStartFormat`). `dir` yazmak testi sözleşmeden koparırdı.
        if let directory { payload += ";pwd=\(base64(directory))" }
        return payload + "\u{07}"
    }

    private func end(_ exitCode: Int) -> String { "\u{1B}]133;D;\(exitCode)\u{07}" }

    private func feed(_ recorder: inout CommandBlockRecorder, _ text: String, at date: Date) {
        recorder.consume(Array(text.utf8), now: date)
    }

    private var epoch: Date { Date(timeIntervalSince1970: 1_000) }

    @Test func aCompleteCommandBecomesOneFinishedBlock() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, start("echo hi", directory: "/tmp"), at: epoch)
        feed(&recorder, "hi\r\n", at: epoch.addingTimeInterval(0.2))
        feed(&recorder, end(0), at: epoch.addingTimeInterval(1.5))

        #expect(recorder.blocks.count == 1)
        let block = try! #require(recorder.blocks.first)
        #expect(block.command == "echo hi")
        #expect(block.workingDirectory == "/tmp")
        #expect(block.output == "hi")
        #expect(block.exitCode == 0)
        #expect(block.state == .succeeded)
        #expect(block.duration(now: epoch) == 1.5)
    }

    /// Sıfırdan farklı çıkış kodu başarısızlıktır ve kod blokta GÖRÜNÜR.
    @Test func aNonZeroExitCodeMakesTheBlockFail() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, start("false"), at: epoch)
        feed(&recorder, end(1), at: epoch.addingTimeInterval(0.1))

        #expect(recorder.blocks.first?.state == .failed(exitCode: 1))
    }

    /// Çıktı YALNIZ açık bloğa yazılır. Yanlış bloğa düşseydi kullanıcının okuduğu her
    /// blok yalan olurdu — bu tarayıcının var oluş sebebi.
    @Test func outputLandsOnlyOnTheBlockThatWasRunning() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, start("first") + "one\r\n" + end(0), at: epoch)
        feed(&recorder, start("second") + "two\r\n" + end(0), at: epoch.addingTimeInterval(1))

        #expect(recorder.blocks.map(\.output) == ["one", "two"])
        #expect(recorder.blocks.map(\.command) == ["first", "second"])
    }

    /// Kabuk `D` yaymadan yeni komut başlarsa (kanca yarım kurulu, kullanıcı Ctrl-C'ledi)
    /// önceki blok AÇIK KALMAMALI: sonsuza kadar "Running" gösteren bir blok yalandır.
    @Test func aNewCommandClosesAPreviousBlockThatNeverEnded() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, start("first"), at: epoch)
        feed(&recorder, start("second"), at: epoch.addingTimeInterval(2))

        #expect(recorder.blocks.count == 2)
        // Kod bilinmiyor: 0 varsaymak başarısızı başarılı göstermek olurdu.
        #expect(recorder.blocks.first?.state == .finished)
        #expect(recorder.blocks.first?.finishedAt == epoch.addingTimeInterval(2))
        #expect(recorder.blocks.last?.isRunning == true)
    }

    /// Shell integration kurulu değilse hiç işaret gelmez. O zaman blok da YOKTUR —
    /// komut adı bilinmeyen bir "blok" uydurmak, kullanıcıya sahte yapı göstermek olurdu.
    @Test func outputWithoutAnyMarkerProducesNoBlocks() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, "plain shell output\r\n", at: epoch)

        #expect(recorder.blocks.isEmpty)
    }

    @Test func aRunningBlockIsVisibleBeforeItFinishes() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, start("sleep 5"), at: epoch)
        feed(&recorder, "working…", at: epoch.addingTimeInterval(1))

        let block = try! #require(recorder.blocks.first)
        #expect(block.isRunning)
        #expect(block.state == .running)
        #expect(block.output == "working…")
        // Süre çalışırken `now`'a göre büyür.
        #expect(block.duration(now: epoch.addingTimeInterval(3)) == 3)
    }

    /// Bellek sınırı: en ESKİ blok düşer. Sınır olmasaydı uzun bir oturum belleği
    /// sınırsız büyütürdü (briefs/2 "Performans Gereksinimleri").
    @Test func theOldestBlockDropsOnceTheLimitIsReached() {
        var recorder = CommandBlockRecorder()
        for index in 0..<(CommandBlockLimits.maxBlocks + 5) {
            feed(&recorder, start("cmd\(index)") + end(0), at: epoch.addingTimeInterval(Double(index)))
        }

        #expect(recorder.blocks.count == CommandBlockLimits.maxBlocks)
        #expect(recorder.blocks.first?.command == "cmd5")
        #expect(recorder.blocks.last?.command == "cmd\(CommandBlockLimits.maxBlocks + 4)")
    }

    /// Kanca komut metnini bildirmezse blok yine kurulur ama metin UYDURULMAZ.
    @Test func aMarkerWithoutACommandStillOpensABlock() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, "\u{1B}]133;C\u{07}output\r\n" + end(0), at: epoch)

        #expect(recorder.blocks.count == 1)
        #expect(recorder.blocks.first?.command == nil)
        #expect(recorder.blocks.first?.output == "output")
    }

    /// Çıktı sınırı aşıldığında blok bunu SÖYLER; kullanıcı eksik bir çıktıya tam
    /// sanarak bakmamalı.
    @Test func aTruncatedBlockSaysSo() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, start("yes"), at: epoch)
        let line = String(repeating: "x", count: 1_000) + "\r\n"
        for _ in 0..<((CommandBlockLimits.maxOutputCharacters / 1_000) + 5) {
            feed(&recorder, line, at: epoch)
        }

        #expect(recorder.blocks.first?.didTruncateOutput == true)
    }

    /// Blokları temizlemek yalnız listeyi boşaltır; açık blok kalmaz.
    @Test func clearingRemovesEveryBlock() {
        var recorder = CommandBlockRecorder()
        feed(&recorder, start("echo hi") + "hi\r\n", at: epoch)

        recorder.clear()

        #expect(recorder.blocks.isEmpty)
    }
}
