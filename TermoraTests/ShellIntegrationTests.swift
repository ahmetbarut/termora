import Foundation
import Testing
@testable import Termora

/// briefs/1 "İkinci Aşama Özellikleri" ▸ Shell integration; briefs/2 Onboarding adım 3;
/// briefs/3 Ekran 3.
///
/// Bu, Termora'nın KULLANICININ KENDİ DOSYASINA yazan tek özelliği. Bu yüzden testlerin
/// çoğu yeteneği değil, geri alınabilirliği ve zarar vermezliği sabitliyor.
@Suite("Shell integration")
struct ShellIntegrationTests {

    // MARK: - Shell ailesini tanıma

    @Test func theFamilyComesFromTheShellPath() {
        #expect(ShellFamily(shellPath: "/bin/zsh") == .zsh)
        #expect(ShellFamily(shellPath: "/opt/homebrew/bin/zsh") == .zsh)
        #expect(ShellFamily(shellPath: "/bin/bash") == .bash)
        #expect(ShellFamily(shellPath: "/usr/local/bin/bash") == .bash)
    }

    /// Desteklenmeyen bir shell (fish, nushell) SESSİZCE zsh sayılmaz: yanlış sözdizimini
    /// kullanıcının rc dosyasına yazmak onun kabuğunu açılmaz hâle getirebilirdi.
    @Test func anUnsupportedShellIsNotGuessed() {
        #expect(ShellFamily(shellPath: "/opt/homebrew/bin/fish") == nil)
        #expect(ShellFamily(shellPath: "/bin/ksh") == nil)
        #expect(ShellFamily(shellPath: "") == nil)
    }

    @Test func eachFamilyKnowsItsStartupFile() {
        #expect(ShellFamily.zsh.startupFileName == ".zshrc")
        #expect(ShellFamily.bash.startupFileName == ".bash_profile")
    }

    // MARK: - Parçacık

    /// Parçacık OSC 133 işaretlerini yayar; Termora komutun ne zaman başladığını, ne zaman
    /// bittiğini ve çıkış kodunu bu sayede BİLİR (tahmin etmez).
    @Test func theSnippetEmitsTheFourOSC133Markers() {
        for family in [ShellFamily.zsh, .bash] {
            let snippet = ShellIntegration.snippet(for: family)
            #expect(snippet.contains("133;A"))
            #expect(snippet.contains("133;B"))
            #expect(snippet.contains("133;C"))
            #expect(snippet.contains("133;D"))
        }
    }

    /// Parçacık İKİ KEZ kaynak alınırsa kancalar iki kez kurulmaz; kullanıcı rc dosyasını
    /// elle yeniden yükleyebilir ve her prompt iki kat işaret yayardı.
    @Test func theSnippetGuardsAgainstBeingSourcedTwice() {
        for family in [ShellFamily.zsh, .bash] {
            #expect(ShellIntegration.snippet(for: family).contains(ShellIntegration.guardVariable))
        }
    }

    /// Parçacık ETKİLEŞİMSİZ kabukta hiçbir şey yapmaz: bir betiğin `bash script.sh`
    /// çıktısına kaçış dizisi karıştırmak çıktıyı ayrıştıran her aracı bozardı.
    @Test func theSnippetDoesNothingInANonInteractiveShell() {
        #expect(ShellIntegration.snippet(for: .zsh).contains("$-"))
        #expect(ShellIntegration.snippet(for: .bash).contains("$-"))
    }

    /// `C` işareti komut METNİNİ taşır (briefs/2 komut bloklarının "Girilen komut" alanı).
    ///
    /// OSC 133 standardı bunu vermez; kanca eklemezse Termora'nın komutu öğrenmesinin tek
    /// yolu ekran metnini geri okumak olurdu — kaydırma, satır kaydırma ve renk dizileri
    /// yüzünden güvenilmez bir tahmin. Kanca kaynağı bilir, biz de ondan alıyoruz.
    @Test func theSnippetSendsTheCommandTextAndDirectoryWithTheOutputStartMarker() {
        for family in [ShellFamily.zsh, .bash] {
            let snippet = ShellIntegration.snippet(for: family)
            #expect(snippet.contains("133;C;cmd=%s;pwd=%s"), "\(family) komut metnini taşımıyor")
            // Metin base64 gider: ham komut `;` ve BEL içerebilir, ikisi de OSC dizisini bozar.
            #expect(snippet.contains("base64"), "\(family) komutu kodlamadan gönderiyor")
        }
    }

    /// zsh komut metnini `preexec`'in ARGÜMANINDAN alır — kabuğun kullanıcıdan okuduğu
    /// satırın kendisi. Ekrandan geri okuma yapılmaz.
    @Test func zshReadsTheCommandFromItsPreexecArgument() {
        #expect(ShellIntegration.snippet(for: .zsh).contains("preexec"))
        #expect(ShellIntegration.snippet(for: .zsh).contains("\"$1\""))
    }

    /// bash'in DEBUG kancası HER basit komuttan önce ateşlenir: `PROMPT_COMMAND`'in
    /// parçaları da dahil. Kurulmuş bir bayrak olmadan her prompt için sahte bir komut
    /// bloğu açılır ve blok listesi çöple dolardı.
    @Test func bashFiresTheOutputStartMarkerOncePerCommandNotOncePerDebugTrap() {
        let snippet = ShellIntegration.snippet(for: .bash)
        #expect(snippet.contains("DEBUG"))
        #expect(snippet.contains("__TERMORA_ARMED"))
        // Bayrak prompt'un SONUNDA kurulur; erken kurulursa PROMPT_COMMAND'in kendi
        // komutları onu tüketir ve kullanıcının gerçek komutu işaretsiz kalırdı.
        #expect(snippet.contains("__termora_arm"))
    }

    /// DEBUG kancası `extdebug` açıkken sıfırdan farklı dönerse bash SONRAKİ KOMUTU ATLAR.
    /// Kullanıcının komutunun çalışmaması, bu özelliğin verebileceği en büyük zarardır.
    @Test func theBashDebugHookAlwaysReturnsSuccess() {
        #expect(ShellIntegration.snippet(for: .bash).contains("return 0"))
    }

    /// Gerçek bir bash'te yakalandı: kullanıcı BOŞ SATIRDA Enter'a bastığında hiçbir komut
    /// çalışmaz, ama `PROMPT_COMMAND` yine döner ve DEBUG kancası bu kez Termora'nın KENDİ
    /// prompt fonksiyonunu "kullanıcının komutu" sanıp `cmd=__termora_prompt` yayardı.
    /// Blok listesi her Enter'da sahte bir blokla dolardı.
    ///
    /// İki kilit birlikte durur:
    /// 1. Kendi fonksiyon adlarımız kancada elenir.
    /// 2. Bayrak prompt'un BAŞINDA düşürülür; kullanıcının kendi `PROMPT_COMMAND`
    ///    girdileri (`history -a` gibi) de komut sanılmasın.
    @Test func bashNeverReportsItsOwnPromptHooksAsTheUsersCommand() {
        let snippet = ShellIntegration.snippet(for: .bash)

        #expect(snippet.contains("__termora_*"), "kendi kanca adlarımız elenmiyor")
        // `__termora_prompt` bayrağı DÜŞÜRÜR: kullanıcının PROMPT_COMMAND girdileri
        // ondan sonra çalışır ve armed bir bayrak bulmamalıdır.
        let promptBody = snippet.components(separatedBy: "__termora_prompt() {")
        #expect(promptBody.count == 2, "prompt fonksiyonu bulunamadı")
        #expect(promptBody.last?.contains("__TERMORA_ARMED=") == true,
                "prompt bayrağı düşürmüyor")
    }

    // MARK: - Kurulum: metin dönüşümü SAFTIR

    private let emptyRC = "export PATH=/usr/local/bin:$PATH\n"

    @Test func installingAppendsAClearlyMarkedBlock() {
        let updated = ShellIntegration.installing(into: emptyRC, family: .zsh)

        #expect(updated.hasPrefix(emptyRC), "kullanıcının kendi satırları korunmadı")
        #expect(updated.contains(ShellIntegration.beginMarker))
        #expect(updated.contains(ShellIntegration.endMarker))
        #expect(ShellIntegration.isInstalled(in: updated))
    }

    /// İki kez kurmak dosyaya iki blok BIRAKMAZ; kullanıcı düğmeye iki kez basabilir.
    @Test func installingTwiceLeavesExactlyOneBlock() {
        let once = ShellIntegration.installing(into: emptyRC, family: .zsh)
        let twice = ShellIntegration.installing(into: once, family: .zsh)

        #expect(twice.components(separatedBy: ShellIntegration.beginMarker).count - 1 == 1)
    }

    /// Kaldırma BLOĞU alır, kullanıcının satırlarını bırakır. Tam geri alınabilirlik:
    /// kur→kaldır dosyayı ORİJİNALİNE döndürür.
    @Test func uninstallingRestoresTheFileExactly() {
        let installed = ShellIntegration.installing(into: emptyRC, family: .zsh)
        #expect(ShellIntegration.uninstalling(from: installed) == emptyRC)
    }

    @Test func uninstallingAFileWithoutTheBlockChangesNothing() {
        #expect(ShellIntegration.uninstalling(from: emptyRC) == emptyRC)
        #expect(!ShellIntegration.isInstalled(in: emptyRC))
    }

    /// Blok kurulurken dosyanın sonunda satır sonu yoksa eklenir: yoksa Termora'nın ilk
    /// satırı kullanıcının son satırına YAPIŞIR ve ikisi de bozulur.
    @Test func aFileWithoutATrailingNewlineIsNotCorrupted() {
        let noNewline = "alias ll='ls -la'"
        let updated = ShellIntegration.installing(into: noNewline, family: .zsh)

        #expect(updated.contains("alias ll='ls -la'\n"))
        #expect(!updated.contains("ls -la'# "))
        #expect(ShellIntegration.uninstalling(from: updated).hasPrefix(noNewline))
    }

    // MARK: - OSC 133 ayrıştırma

    @Test func promptAndCommandMarkersAreRecognised() {
        #expect(ShellIntegrationMarker(payload: "133;A") == .promptStart)
        #expect(ShellIntegrationMarker(payload: "133;B") == .commandStart)
        #expect(ShellIntegrationMarker(payload: "133;C") == .outputStart(command: nil, directory: nil))
    }

    // MARK: - `C` işaretinin taşıdığı komut metni ve dizin

    private func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Komut BLOKLARININ can damarı (briefs/2 "Girilen komut", "Çalışma dizini").
    ///
    /// OSC 133'ün kendisi komutun metnini VERMEZ; Termora'nın kancası onu `cmd=` alanında
    /// taşır. Bu çözülmezse her blok "komut metni yok" derdi ve "yeniden çalıştır",
    /// "düzenleyerek çalıştır", "Markdown'a aktar" eylemlerinin hiçbiri yapılamazdı.
    @Test func theOutputStartMarkerCarriesTheCommandAndItsDirectory() {
        let payload = "133;C;cmd=\(base64("npm run build"));pwd=\(base64("/Users/dev/pinro"))"

        #expect(ShellIntegrationMarker(payload: payload)
                == .outputStart(command: "npm run build", directory: "/Users/dev/pinro"))
    }

    /// Komut metni base64 GİDER çünkü ham hâli OSC dizisini bozardı: `;` alanları böler,
    /// BEL (`\u{07}`) diziyi ERKEN BİTİRİR ve kalan karakterler doğrudan ekrana basılırdı.
    /// Kodlanmış hâlde noktalı virgül, tırnak, satır sonu ve UTF-8 sağ salim geçer.
    @Test func aCommandFullOfSeparatorsSurvivesTheRoundTrip() {
        let nasty = "echo 'a;b' && printf 'ü\nç'"
        let marker = ShellIntegrationMarker(payload: "133;C;cmd=\(base64(nasty))")

        #expect(marker == .outputStart(command: nasty, directory: nil))
    }

    /// Başka bir terminalin kancası (ya da `base64` bulunamayan bir sistem) düz `133;C`
    /// yayar. Termora komut metni UYDURMAZ — alan nil kalır ve blok bunu dürüstçe söyler.
    @Test func aPlainOutputStartMarkerLeavesTheCommandUnknown() {
        #expect(ShellIntegrationMarker(payload: "133;C") == .outputStart(command: nil, directory: nil))
        #expect(ShellIntegrationMarker(payload: "133;C;cmd=") == .outputStart(command: nil, directory: nil))
    }

    /// Çözülemeyen bir yük ATILIR. Yarım çözülmüş bir komut metni göstermek, kullanıcının
    /// "yeniden çalıştır" diyebileceği YANLIŞ bir komut üretirdi.
    @Test func anUndecodableCommandFieldIsDroppedRatherThanShownHalfway() {
        #expect(ShellIntegrationMarker(payload: "133;C;cmd=!!!not-base64!!!")
                == .outputStart(command: nil, directory: nil))
        // Geçerli base64 ama geçerli UTF-8 değil.
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD]).base64EncodedString()
        #expect(ShellIntegrationMarker(payload: "133;C;cmd=\(invalidUTF8)")
                == .outputStart(command: nil, directory: nil))
    }

    /// Tanımadığımız ek alanlar (`aid=`, ileride eklenecek başkaları) `C`'yi bozmaz.
    @Test func unknownFieldsOnTheOutputStartMarkerAreIgnored() {
        let payload = "133;C;aid=\(base64("42"));cmd=\(base64("ls"))"

        #expect(ShellIntegrationMarker(payload: payload) == .outputStart(command: "ls", directory: nil))
    }

    @Test func theEndMarkerCarriesTheExitCode() {
        #expect(ShellIntegrationMarker(payload: "133;D;0") == .commandEnd(exitCode: 0))
        #expect(ShellIntegrationMarker(payload: "133;D;127") == .commandEnd(exitCode: 127))
    }

    /// Çıkış kodu OLMADAN gelen `D` (bazı kabuklar böyle yayar) kod UYDURMAZ: 0 varsaymak
    /// başarısız bir komutu başarılı göstermek olurdu.
    @Test func anEndMarkerWithoutACodeDoesNotInventOne() {
        #expect(ShellIntegrationMarker(payload: "133;D") == .commandEnd(exitCode: nil))
    }

    /// Ek parametreler (`aid=`, `cl=`) ayrıştırmayı bozmaz — başka terminaller de yayar.
    @Test func extraParametersAreIgnored() {
        #expect(ShellIntegrationMarker(payload: "133;D;1;aid=42") == .commandEnd(exitCode: 1))
        #expect(ShellIntegrationMarker(payload: "133;A;cl=m") == .promptStart)
    }

    // MARK: - Diske yazan kurulumcu

    /// Sahte dosya sistemi: hiçbir test kullanıcının gerçek rc dosyasına dokunmaz.
    @MainActor
    private final class FakeFiles: ShellIntegrationFileStoring {
        var contents: [String: String] = [:]
        private(set) var writes: [String] = []

        func read(_ path: String) throws -> String? { contents[path] }
        func write(_ text: String, to path: String) throws {
            contents[path] = text
            writes.append(path)
        }
    }

    @MainActor
    @Test func installingWritesTheBlockAndKeepsABackupFirst() throws {
        let files = FakeFiles()
        let rc = "/Users/test/.zshrc"
        files.contents[rc] = "alias ll='ls -la'\n"
        let installer = ShellIntegrationInstaller(home: "/Users/test", files: files)

        try installer.install(for: .zsh)

        #expect(ShellIntegration.isInstalled(in: try #require(files.contents[rc])))
        // Yedek ÖNCE yazılır: kullanıcının dosyası bir hata hâlinde kaybolmaz.
        let backup = try #require(files.contents[rc + ShellIntegrationInstaller.backupSuffix])
        #expect(backup == "alias ll='ls -la'\n")
        #expect(files.writes.first == rc + ShellIntegrationInstaller.backupSuffix)
    }

    /// rc dosyası HİÇ YOKSA kurulum yine çalışır (yeni kullanıcı) ve boş bir yedek
    /// üretmez — silinecek bir şey yoktu.
    @MainActor
    @Test func installingWorksWhenTheStartupFileDoesNotExistYet() throws {
        let files = FakeFiles()
        let installer = ShellIntegrationInstaller(home: "/Users/test", files: files)

        try installer.install(for: .bash)

        #expect(ShellIntegration.isInstalled(in: try #require(files.contents["/Users/test/.bash_profile"])))
        #expect(files.contents["/Users/test/.bash_profile" + ShellIntegrationInstaller.backupSuffix] == nil)
    }

    @MainActor
    @Test func uninstallingPutsTheFileBackAndTheStatusFollows() throws {
        let files = FakeFiles()
        let rc = "/Users/test/.zshrc"
        files.contents[rc] = "alias ll='ls -la'\n"
        let installer = ShellIntegrationInstaller(home: "/Users/test", files: files)
        try installer.install(for: .zsh)
        #expect(installer.isInstalled(for: .zsh))

        try installer.uninstall(for: .zsh)

        #expect(files.contents[rc] == "alias ll='ls -la'\n")
        #expect(!installer.isInstalled(for: .zsh))
    }

    /// Zaten kuruluyken tekrar kurmak yedeği KURULU hâlle ezmez; yoksa ilk yedek
    /// (kullanıcının gerçek dosyası) kaybolurdu.
    @MainActor
    @Test func reinstallingDoesNotOverwriteTheOriginalBackup() throws {
        let files = FakeFiles()
        let rc = "/Users/test/.zshrc"
        files.contents[rc] = "original\n"
        let installer = ShellIntegrationInstaller(home: "/Users/test", files: files)

        try installer.install(for: .zsh)
        try installer.install(for: .zsh)

        #expect(files.contents[rc + ShellIntegrationInstaller.backupSuffix] == "original\n")
    }

    @Test func unrelatedOrMalformedPayloadsAreRejected() {
        #expect(ShellIntegrationMarker(payload: "7;file:///tmp") == nil)
        #expect(ShellIntegrationMarker(payload: "133;Z") == nil)
        #expect(ShellIntegrationMarker(payload: "133") == nil)
        #expect(ShellIntegrationMarker(payload: "") == nil)
        #expect(ShellIntegrationMarker(payload: "133;D;not-a-number") == .commandEnd(exitCode: nil))
    }
}
