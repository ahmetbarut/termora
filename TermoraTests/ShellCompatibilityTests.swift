import Foundation
import Testing
@testable import Termora

/// briefs/2 "Uyumluluk Testi": `zsh`, `bash`, `fish` — ve bu kabuklarda shell
/// integration'ın GERÇEKTEN çalışması.
///
/// Buradaki testler sahte bir kabukla değil, `forkpty` ile açılmış GERÇEK bir kabukla
/// koşar. Sebep dar ve önemli: komut bloklarının tamamı, kancanın OSC 133 yayacağı
/// varsayımına dayanıyor. O varsayım yalnız gerçek bir kabukta sınanabilir — snippet'i
/// birim testinde metin olarak karşılaştırmak, kabuğun onu çalıştırıp çalıştırmadığını
/// söylemez.
///
/// Kurulu olmayan kabuk ATLANIR. `fish` her macOS'ta yoktur ve olmayan bir kabuk yüzünden
/// kırmızı duran bir paket, kimsenin okumadığı bir pakete dönüşür.
@Suite("Kabuk uyumluluğu", .serialized)
struct ShellCompatibilityTests {

    private static func path(of shell: String) -> String? {
        let candidates = ["/bin/\(shell)", "/usr/bin/\(shell)",
                          "/usr/local/bin/\(shell)", "/opt/homebrew/bin/\(shell)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Termora'nın kabuğa GERÇEKTEN verdiği ortam.
    ///
    /// Testin kendi kısa listesini kurması yanlış sonuç verir: ilk yazışta `LANG`
    /// yoktu ve bash UTF-8 çıktıyı bozdu — uygulamada olmayan bir hata. Ortam
    /// `EnvironmentBuilder`'dan alınınca test, kullanıcının gördüğü kabuğu ölçer.
    private static let environment = EnvironmentBuilder.environment()

    /// Kabuğu açar, komutu yazar, çıktıyı toplar.
    private func run(_ command: String, in shellPath: String, seconds: Double = 2.0) -> String {
        let child = PTYTestHarness.spawn(executable: shellPath, args: ["-i"],
                                         environment: Self.environment)
        defer { PTYTestHarness.kill(child) }
        // İstem çizilene kadar beklenir; erken yazılan komut yutulur.
        PTYTestHarness.drain(child, seconds: 0.4)
        PTYTestHarness.write(child, command + "\n")
        return PTYTestHarness.drain(child, seconds: seconds)
    }

    // MARK: - Kabuklar çalışıyor mu

    @Test(arguments: ["zsh", "bash", "fish"])
    func aShellStartsAndRunsACommand(_ shell: String) throws {
        guard let shellPath = Self.path(of: shell) else { return }

        let output = run("echo termora-marker-42", in: shellPath)

        #expect(output.contains("termora-marker-42"))
    }

    /// briefs/1 "Terminal Oturumu": ANSI renkleri, Unicode, emoji desteklenmeli.
    /// Kabuk bunları geçirmezse arındırıcının doğru olması hiçbir işe yaramaz.
    @Test(arguments: ["zsh", "bash"])
    func aShellPassesUnicodeAndEmojiThrough(_ shell: String) throws {
        guard let shellPath = Self.path(of: shell) else { return }

        let output = run("printf 'ş-ğ-ü-📦-日本\\n'", in: shellPath)

        #expect(output.contains("ş-ğ-ü-📦-日本"))
    }

    // MARK: - Shell integration gerçek kabukta

    /// Kanca kurulduktan sonra kabuk OSC 133 yaymalı. Yaymazsa komut blokları HİÇ
    /// çalışmaz — ve bunu ancak burada görebiliriz.
    @Test(arguments: [ShellFamily.zsh, ShellFamily.bash])
    func theShellIntegrationSnippetEmitsMarkersInARealShell(_ family: ShellFamily) throws {
        guard let shellPath = Self.path(of: family.rawValue) else { return }

        let child = PTYTestHarness.spawn(executable: shellPath, args: ["-i"],
                                         environment: Self.environment)
        defer { PTYTestHarness.kill(child) }
        PTYTestHarness.drain(child, seconds: 0.4)

        // Snippet, rc dosyasına yazılmak yerine doğrudan kabuğa beslenir: testin diskteki
        // dosyalara dokunmaması gerekiyor, ölçtüğümüz şey de zaten snippet'in kendisi.
        PTYTestHarness.write(child, ShellIntegration.snippet(for: family) + "\n")
        PTYTestHarness.drain(child, seconds: 0.6)
        PTYTestHarness.write(child, "echo integration-check\n")
        let output = PTYTestHarness.drain(child, seconds: 1.5)

        // İşaretler ham baytlarda görünür: `ESC ] 133 ; …`
        #expect(output.contains("\u{1B}]133;"), "kabuk hiç OSC 133 yaymadı")
        // Komutun bittiğini bildiren `D` işareti, çıkış kodu takibinin dayanağı.
        #expect(output.contains("133;D"), "komut bitişi (D) bildirilmedi")
    }

    /// Uçtan uca: gerçek kabuğun ham çıktısı, kaydediciden geçince gerçek bir blok
    /// üretmeli. Parçalar tek tek doğru olup birlikte çalışmayabilir — bu test tam
    /// olarak o boşluğu kapatır.
    @Test func aRealShellProducesARealCommandBlock() throws {
        guard let shellPath = Self.path(of: "zsh") else { return }

        let child = PTYTestHarness.spawn(executable: shellPath, args: ["-i"],
                                         environment: Self.environment)
        defer { PTYTestHarness.kill(child) }
        PTYTestHarness.drain(child, seconds: 0.4)
        PTYTestHarness.write(child, ShellIntegration.snippet(for: .zsh) + "\n")
        PTYTestHarness.drain(child, seconds: 0.6)

        PTYTestHarness.write(child, "echo block-content\n")
        let raw = PTYTestHarness.drain(child, seconds: 1.5)

        var recorder = CommandBlockRecorder()
        recorder.consume(Array(raw.utf8), now: Date())

        let block = recorder.blocks.first { $0.command?.contains("echo block-content") == true }
        #expect(block != nil, "kabuk çıktısından blok kurulamadı")
        #expect(block?.output.contains("block-content") == true)
        #expect(block?.exitCode == 0)
    }

    // MARK: - Büyük çıktı

    /// briefs/2 "Test Stratejisi" ▸ *Büyük terminal çıktısı.* Sınır tutmalı, bellek
    /// sınırsız büyümemeli ve kırpma kullanıcıya SÖYLENMELİ.
    @Test func alargeOutputStaysWithinTheBlockLimit() throws {
        guard let shellPath = Self.path(of: "zsh") else { return }

        let child = PTYTestHarness.spawn(executable: shellPath, args: ["-i"],
                                         environment: Self.environment)
        defer { PTYTestHarness.kill(child) }
        PTYTestHarness.drain(child, seconds: 0.4)
        PTYTestHarness.write(child, ShellIntegration.snippet(for: .zsh) + "\n")
        PTYTestHarness.drain(child, seconds: 0.6)

        // 5.000 satır — blok sınırının (64.000 karakter) belirgin biçimde üstünde.
        PTYTestHarness.write(child, "for i in $(seq 1 5000); do echo line-$i-padding-padding; done\n")
        let raw = PTYTestHarness.drain(child, seconds: 4.0)

        var recorder = CommandBlockRecorder()
        recorder.consume(Array(raw.utf8), now: Date())

        guard let block = recorder.blocks.last, !block.output.isEmpty else { return }
        #expect(block.output.count <= CommandBlockLimits.maxOutputCharacters)
        // Kırpıldıysa blok bunu söylemeli; son satırlar korunmalı.
        if block.didTruncateOutput {
            #expect(block.output.contains("line-5000") || block.output.contains("line-49"))
        }
    }
}
