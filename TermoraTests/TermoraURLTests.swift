import Foundation
import Testing
@testable import Termora

/// briefs/2 "Hızlı Açma": `termora://open?path=…`.
///
/// GÜVENLİK: bu ayrıştırıcı uygulamanın DIŞINDAN — herhangi bir web sayfasından —
/// tetiklenebilir. Bu yüzden testlerin çoğu "ne KABUL EDİLİR" değil, "ne REDDEDİLİR"
/// sorusunu yanıtlar. Ayrıştırıcı saftır: dosya sistemine yalnız enjekte edilen
/// `isDirectory` kapanışı üzerinden bakar.
@Suite("termora:// URL şeması")
struct TermoraURLTests {

    private let home = "/Users/ahmet"

    /// Testlerin varsayılan dünyası: yalnız bu yollar klasördür.
    private let folders: Set<String> = ["/Users/ahmet/Projects/pinro",
                                        "/Users/ahmet/Projects",
                                        "/Users/ahmet",
                                        "/etc",
                                        "/"]

    private func parse(_ string: String,
                       files: Set<String> = []) -> Result<TermoraURL.Request, TermoraURL.Rejection> {
        guard let url = URL(string: string) else {
            return .failure(.notATermoraURL)
        }
        return TermoraURL.parse(url, home: home) { path in
            folders.contains(path) && !files.contains(path)
        }
    }

    // MARK: - Kabul edilen biçim

    @Test func opensAnExistingFolder() {
        #expect(parse("termora://open?path=/Users/ahmet/Projects/pinro")
                == .success(.openFolder(path: "/Users/ahmet/Projects/pinro")))
    }

    @Test func percentEncodingIsDecoded() {
        #expect(parse("termora://open?path=%2FUsers%2Fahmet%2FProjects%2Fpinro")
                == .success(.openFolder(path: "/Users/ahmet/Projects/pinro")))
    }

    @Test func tildeIsExpanded() {
        #expect(parse("termora://open?path=~/Projects/pinro")
                == .success(.openFolder(path: "/Users/ahmet/Projects/pinro")))
    }

    /// Yolun içindeki `..` çözülür; sonuç yine var olan bir klasör olmak zorundadır.
    @Test func dotDotInsideThePathIsResolvedBeforeTheFolderCheck() {
        #expect(parse("termora://open?path=/Users/ahmet/Projects/../Projects/pinro")
                == .success(.openFolder(path: "/Users/ahmet/Projects/pinro")))
    }

    /// `..` kökün üstüne çıkamaz — "/../../etc" kabuğa değil, `/etc` klasörüne çözülür.
    @Test func dotDotCannotClimbAboveTheRoot() {
        #expect(parse("termora://open?path=/../../etc") == .success(.openFolder(path: "/etc")))
    }

    /// Şema adı büyük/küçük harfe duyarsızdır (RFC 3986).
    @Test func theSchemeIsCaseInsensitive() {
        #expect(parse("TERMORA://open?path=/etc") == .success(.openFolder(path: "/etc")))
    }

    /// `termora:open?…` (çift eğik çizgisiz) biçimi de aynı isteği anlatır.
    @Test func theOpaqueFormIsAcceptedToo() {
        #expect(parse("termora:open?path=/etc") == .success(.openFolder(path: "/etc")))
    }

    /// Sorgu dizesinde `+` FORM kodlaması değildir: dosya adında geçen artı korunur.
    @Test func aPlusSignStaysAPlusSignInsideAPath() throws {
        let url = try #require(URL(string: "termora://open?path=/tmp/c+%2B"))
        let outcome = TermoraURL.parse(url, home: home) { $0 == "/tmp/c++" }
        #expect(outcome == .success(.openFolder(path: "/tmp/c++")))
    }

    // MARK: - GÜVENLİK: komut çalıştırma YOKTUR

    /// Şemanın TEK yeteneği klasör açmaktır. `command` gibi bir parametre "yok sayılmaz",
    /// URL'in TAMAMINI reddettirir: sessizce yok saymak, ileride eklenecek bir parametrenin
    /// eski sürümlerde fark edilmeden düşmesine yol açardı.
    @Test func aCommandParameterIsNeverSupported() {
        #expect(parse("termora://open?command=rm+-rf+~")
                == .failure(.unsupportedParameter("command")))
    }

    /// Geçerli bir yolun YANINA iliştirilen komut da URL'i düşürür — "yolu aç, komutu at"
    /// davranışı saldırgana yeniden deneme imkânı verirdi.
    @Test func aValidPathDoesNotRescueAURLThatAlsoCarriesACommand() {
        #expect(parse("termora://open?path=/etc&command=rm%20-rf%20/")
                == .failure(.unsupportedParameter("command")))
    }

    @Test func everyUnknownParameterIsRejected() {
        for name in ["exec", "run", "args", "shell", "startupCommand", "script"] {
            #expect(parse("termora://open?path=/etc&\(name)=x")
                    == .failure(.unsupportedParameter(name)))
        }
    }

    /// `open` dışında hiçbir eylem yoktur.
    @Test func onlyTheOpenActionExists() {
        #expect(parse("termora://run?path=/etc") == .failure(.unsupportedAction("run")))
        #expect(parse("termora://exec?path=/etc") == .failure(.unsupportedAction("exec")))
    }

    @Test func extraPathSegmentsAfterTheActionAreRejected() {
        #expect(parse("termora://open/etc/passwd?path=/etc")
                == .failure(.unsupportedAction("open/etc/passwd")))
    }

    @Test func anotherApplicationsSchemeIsNotOurs() {
        #expect(parse("https://example.com/open?path=/etc") == .failure(.notATermoraURL))
        #expect(parse("file:///etc") == .failure(.notATermoraURL))
    }

    // MARK: - Eksik / bozuk yol

    @Test func aMissingPathParameterIsRejected() {
        #expect(parse("termora://open") == .failure(.missingPathParameter))
    }

    @Test func anEmptyPathIsRejected() {
        #expect(parse("termora://open?path=") == .failure(.blankPath))
        #expect(parse("termora://open?path=%20%20") == .failure(.blankPath))
    }

    @Test func aRelativePathIsRejected() {
        #expect(parse("termora://open?path=Projects/pinro") == .failure(.notAnAbsolutePath))
        #expect(parse("termora://open?path=../../etc") == .failure(.notAnAbsolutePath))
    }

    /// İki `path` parametresi hangisinin geçerli olduğunu belirsiz bırakır: açılacak
    /// klasör konusunda tahmin yürütülmez.
    @Test func twoPathParametersAreAmbiguousAndRejected() {
        #expect(parse("termora://open?path=/etc&path=/Users/ahmet")
                == .failure(.ambiguousPath))
    }

    // MARK: - Dosya sistemi doğrulaması

    @Test func aPathThatDoesNotExistIsRejected() {
        #expect(parse("termora://open?path=/Users/ahmet/nope") == .failure(.notAFolder))
    }

    /// Dosya yolu açılamaz: hızlı açma yalnız KLASÖR açar.
    @Test func aFilePathIsRejected() {
        #expect(parse("termora://open?path=/Users/ahmet/Projects/pinro",
                      files: ["/Users/ahmet/Projects/pinro"]) == .failure(.notAFolder))
    }

    // MARK: - Finder servisi (aynı doğrulama, farklı kapı)

    /// Servis menüsünden gelen seçim de aynı süzgeçten geçer: dosyalar elenir, klasörler
    /// kanonik yola çevrilir, sıra korunur.
    @Test func theFinderServiceKeepsOnlyFolders() {
        let urls = [URL(fileURLWithPath: "/Users/ahmet/Projects/pinro"),
                    URL(fileURLWithPath: "/Users/ahmet/notes.txt"),
                    URL(fileURLWithPath: "/etc")]

        let paths = FinderService.folderPaths(from: urls, home: home) { folders.contains($0) }

        #expect(paths == ["/Users/ahmet/Projects/pinro", "/etc"])
    }

    @Test func theFinderServiceDropsNonFileURLs() {
        let urls = [URL(string: "https://example.com")].compactMap { $0 }

        #expect(FinderService.folderPaths(from: urls, home: home) { _ in true }.isEmpty)
    }

    /// Aynı klasör iki kez seçilirse tek sekme açılır.
    @Test func theFinderServiceDeduplicates() {
        let urls = [URL(fileURLWithPath: "/etc"), URL(fileURLWithPath: "/etc/")]

        #expect(FinderService.folderPaths(from: urls, home: home) { folders.contains($0) } == ["/etc"])
    }
}
