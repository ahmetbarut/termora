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
        #expect(ShellIntegrationMarker(payload: "133;C") == .outputStart)
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
