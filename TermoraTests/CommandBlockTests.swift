import Foundation
import Testing
@testable import Termora

/// briefs/2 "Komut Blokları" — bir bloğun TAŞIDIĞI bilgiler ve gösterdiği durum.
///
/// Buradaki testlerin ortak derdi tek: blok kullanıcının ekranda gördüğüyle çelişemez.
/// Bir komut başarısız olduysa blok "Succeeded" diyemez; kabuk çıkış kodu bildirmediyse
/// blok bir kod uyduramaz.
@Suite("Command block")
struct CommandBlockTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Durum

    /// Bitiş zamanı yokken komut ÇALIŞIYORDUR. Blok listesi canlıdır; çalışan komutu
    /// "bitti" göstermek, kullanıcıyı çıktının tamamına baktığına inandırırdı.
    @Test func aBlockWithoutAFinishTimeIsStillRunning() {
        let block = CommandBlock(command: "npm run build", startedAt: start)

        #expect(block.state == .running)
        #expect(block.isRunning)
    }

    /// Sıfır çıkış kodu BAŞARIDIR; başka her kod başarısızlıktır (briefs/2).
    @Test func theExitCodeDecidesSuccessOrFailure() {
        let succeeded = CommandBlock(command: "ls", startedAt: start,
                                     finishedAt: start + 1, exitCode: 0)
        let failed = CommandBlock(command: "ls /nope", startedAt: start,
                                  finishedAt: start + 1, exitCode: 1)

        #expect(succeeded.state == .succeeded)
        #expect(failed.state == .failed(exitCode: 1))
        #expect(!succeeded.isRunning)
    }

    /// Kabuk çıkış kodu BİLDİRMEDEN de `D` yayabilir. O hâlde 0 varsaymak başarısız bir
    /// komutu yeşil göstermek olurdu — blok bunun yerine "bitti, kodu bilmiyorum" der.
    @Test func aFinishedBlockWithoutAnExitCodeDoesNotClaimSuccess() {
        let block = CommandBlock(command: "ls", startedAt: start, finishedAt: start + 1)

        #expect(block.state == .finished)
        #expect(block.state != .succeeded)
    }

    /// briefs/2 "Erişilebilirlik": renk TEK durum göstergesi olamaz. Her durumun kendi
    /// sözcüğü, kendi şekli ve kendi VoiceOver cümlesi olmalı — renk körü bir kullanıcı
    /// başarısız komutu ayırt edebilmeli.
    @Test func everyStateCarriesAWordAShapeAndASpokenSentence() {
        let states: [CommandBlockState] = [.running, .succeeded, .failed(exitCode: 127), .finished]

        for state in states {
            #expect(!state.label.isEmpty, "\(state) sözcüksüz")
            #expect(!state.symbolName.isEmpty, "\(state) şekilsiz")
            #expect(!state.accessibilityLabel.isEmpty, "\(state) sessiz")
        }
        // Sözcükler birbirinden ayırt edilebilir olmalı; ikisi aynı olsaydı renk yine
        // tek gösterge hâline gelirdi.
        #expect(Set(states.map(\.label)).count == states.count)
        #expect(Set(states.map(\.symbolName)).count == states.count)
    }

    /// Başarısız bloğun konuşulan etiketi ÇIKIŞ KODUNU söyler: ekranda küçük bir rozette
    /// duran sayıyı VoiceOver kullanıcısı başka türlü duyamazdı.
    @Test func theSpokenLabelOfAFailureNamesTheExitCode() {
        #expect(CommandBlockState.failed(exitCode: 127).accessibilityLabel.contains("127"))
    }

    /// Kodu bilinmeyen bitmiş blok, konuşulan cümlede de kod UYDURMAZ.
    @Test func theSpokenLabelOfAnUnknownOutcomeAdmitsIt() {
        let spoken = CommandBlockState.finished.accessibilityLabel
        #expect(!spoken.contains("0"))
        #expect(spoken.lowercased().contains("exit code"))
    }

    // MARK: - Süre

    /// Çalışan komutun süresi ŞİMDİYE göre büyür; biten komutunki sabittir.
    @Test func aRunningBlockMeasuresAgainstNowAndAFinishedOneDoesNot() {
        let running = CommandBlock(command: "sleep 5", startedAt: start)
        let finished = CommandBlock(command: "ls", startedAt: start, finishedAt: start + 2, exitCode: 0)

        #expect(running.duration(now: start + 5) == 5)
        #expect(finished.duration(now: start + 900) == 2)
    }

    /// Duvar saati geriye atlayabilir (NTP düzeltmesi, uyku/uyanma). "-3s" diye bir süre
    /// yoktur; negatif fark sıfıra kırpılır.
    @Test func aClockThatJumpsBackwardsCannotProduceANegativeDuration() {
        let block = CommandBlock(command: "ls", startedAt: start, finishedAt: start - 10, exitCode: 0)

        #expect(block.duration(now: start) == 0)
        #expect(CommandBlock(command: "ls", startedAt: start).duration(now: start - 10) == 0)
    }

    /// Blokların ÇOĞU saniyenin altındadır. Bildirim biçimlendiricisi onları "0s" diye
    /// okur (orada doğru, burada değil): her bloğun "0s" yazması ölçümü anlamsız kılardı.
    @Test func subSecondCommandsAreShownInMilliseconds() {
        #expect(CommandBlockDuration.text(0.42) == "420 ms")
        #expect(CommandBlockDuration.text(0.004) == "4 ms")
    }

    /// Saniyenin üstünde bildirimlerdeki biçim AYNEN kullanılır — kullanıcı aynı süreyi
    /// iki yerde iki türlü okumamalı.
    @Test func longerCommandsReuseTheNotificationDurationWording() {
        #expect(CommandBlockDuration.text(3) == CommandDurationFormatter.short(3))
        #expect(CommandBlockDuration.text(258) == "4m 18s")
    }

    /// Ölçülemeyen süre çökmez ve sayı uydurmaz.
    @Test func aNonFiniteDurationDoesNotCrashOrInventANumber() {
        #expect(CommandBlockDuration.text(.nan) == "0 ms")
        #expect(CommandBlockDuration.text(-5) == "0 ms")
    }

    // MARK: - Saat

    /// Saat SABİT bir yerelde biçimlenir. Kullanıcının bölge ayarı 12/24 saat biçimini
    /// değiştirseydi aynı ekran iki makinede farklı okunurdu — brief 3 arayüz dilini
    /// İngilizce'ye sabitliyor.
    @Test func theClockIsFormattedInAFixedLocaleNotTheUsers() {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let text = CommandBlockClock.text(noon)

        #expect(text.count == 8, "beklenen biçim HH:mm:ss, gelen: \(text)")
        #expect(text.filter { $0 == ":" }.count == 2)
        #expect(!text.lowercased().contains("am"))
        #expect(!text.lowercased().contains("pm"))
    }
}
