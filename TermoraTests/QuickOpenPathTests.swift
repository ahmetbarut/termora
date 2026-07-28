import Foundation
import Testing
@testable import Termora

/// briefs/2 "Hızlı Açma": son kullanılan / favori klasörlerin ve URL şemasının ORTAK
/// yol mantığı. Saf: dosya sistemine hiç dokunmaz, bu yüzden makineden bağımsız test edilir.
@Suite("Hızlı açma yol normalleştirme")
struct QuickOpenPathTests {

    private let home = "/Users/ahmet"

    // MARK: - Reddedilen girdiler

    @Test func blankInputIsNotAPath() {
        #expect(QuickOpenPath.normalize("", home: home) == nil)
        #expect(QuickOpenPath.normalize("   \n ", home: home) == nil)
    }

    /// Göreli yol KABUL EDİLMEZ: "hangi dizine göre?" sorusunun uygulama içinde tek bir
    /// doğru cevabı yok ve URL şemasından gelen göreli bir yol beklenmedik bir klasör açardı.
    @Test func relativePathsAreRejected() {
        #expect(QuickOpenPath.normalize("Projects/pinro", home: home) == nil)
        #expect(QuickOpenPath.normalize("./pinro", home: home) == nil)
        #expect(QuickOpenPath.normalize("../pinro", home: home) == nil)
    }

    /// `~kullanıcı` biçimi desteklenmez: başka bir kullanıcının ev dizinini çözmek
    /// dizin sunucusuna sorulacak bir iştir ve hızlı açma için gerekli değildir.
    @Test func otherUsersHomeShorthandIsRejected() {
        #expect(QuickOpenPath.normalize("~root/Documents", home: home) == nil)
    }

    @Test func tildeWithoutAKnownHomeIsRejected() {
        #expect(QuickOpenPath.normalize("~/Projects", home: "") == nil)
    }

    // MARK: - Genişletme

    @Test func tildeExpandsToTheGivenHome() {
        #expect(QuickOpenPath.normalize("~", home: home) == "/Users/ahmet")
        #expect(QuickOpenPath.normalize("~/Projects/pinro", home: home) == "/Users/ahmet/Projects/pinro")
    }

    @Test func trailingSlashInHomeDoesNotDoubleUp() {
        #expect(QuickOpenPath.normalize("~/Projects", home: "/Users/ahmet/") == "/Users/ahmet/Projects")
    }

    // MARK: - Kanonikleştirme

    @Test func dotSegmentsAreResolved() {
        #expect(QuickOpenPath.normalize("/Users/ahmet/Projects/../pinro", home: home)
                == "/Users/ahmet/pinro")
        #expect(QuickOpenPath.normalize("/Users/ahmet/./Projects", home: home)
                == "/Users/ahmet/Projects")
    }

    /// `..` kökün üstüne çıkamaz; sonuç her zaman mutlak ve kök altında kalır.
    @Test func parentSegmentsCannotEscapeTheRoot() {
        #expect(QuickOpenPath.normalize("/../../../etc", home: home) == "/etc")
        #expect(QuickOpenPath.normalize("/..", home: home) == "/")
    }

    @Test func repeatedAndTrailingSlashesCollapse() {
        #expect(QuickOpenPath.normalize("/Users//ahmet///Projects/", home: home)
                == "/Users/ahmet/Projects")
    }

    @Test func rootStaysRoot() {
        #expect(QuickOpenPath.normalize("/", home: home) == "/")
        #expect(QuickOpenPath.normalize("///", home: home) == "/")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(QuickOpenPath.normalize("  /Users/ahmet/Projects  ", home: home)
                == "/Users/ahmet/Projects")
    }

    /// Yol içindeki boşluk KORUNUR: kabuk satırı kurulmadığı için kaçış gerekmez
    /// (dizin `startProcess(currentDirectory:)`e verilir, bir komuta gömülmez).
    @Test func spacesInsideThePathSurvive() {
        #expect(QuickOpenPath.normalize("/Users/ahmet/My Projects", home: home)
                == "/Users/ahmet/My Projects")
    }

    @Test func normalizingAnAlreadyNormalPathIsStable() {
        let once = QuickOpenPath.normalize("/Users/ahmet/Projects/../pinro/", home: home)
        #expect(once == QuickOpenPath.normalize(once ?? "", home: home))
    }

    // MARK: - Görünen ad

    @Test func displayNameIsTheLastComponent() {
        #expect(QuickOpenPath.displayName("/Users/ahmet/Projects/pinro") == "pinro")
        #expect(QuickOpenPath.displayName("/Users") == "Users")
    }

    @Test func displayNameOfRootIsTheRootItself() {
        #expect(QuickOpenPath.displayName("/") == "/")
    }
}

/// Palet satırlarına dönüşen birleşik liste (favoriler + son kullanılanlar).
@Suite("Hızlı açma hedeflerinin birleşimi")
struct QuickOpenTargetTests {

    private func folder(_ path: String) -> QuickOpenFolder {
        QuickOpenFolder(path: path)
    }

    @Test func favoritesComeBeforeRecents() {
        let targets = QuickOpenTarget.merged(favorites: [folder("/a")], recents: [folder("/b")])

        #expect(targets.map(\.path) == ["/a", "/b"])
        #expect(targets.map(\.kind) == [.favorite, .recent])
    }

    /// Aynı klasör hem favori hem son kullanılansa TEK satır çizilir — palet satır
    /// kimlikleri benzersiz olmak zorunda (yoksa seçim ve `ForEach` şaşar).
    @Test func aFolderThatIsBothFavoriteAndRecentAppearsOnce() {
        let targets = QuickOpenTarget.merged(favorites: [folder("/a")],
                                             recents: [folder("/a"), folder("/b")])

        #expect(targets.map(\.path) == ["/a", "/b"])
        #expect(targets.map(\.kind) == [.favorite, .recent])
        #expect(Set(targets.map(\.id)).count == targets.count)
    }

    @Test func orderInsideEachListIsPreserved() {
        let targets = QuickOpenTarget.merged(favorites: [folder("/f1"), folder("/f2")],
                                             recents: [folder("/r1"), folder("/r2")])

        #expect(targets.map(\.path) == ["/f1", "/f2", "/r1", "/r2"])
    }

    @Test func emptyListsProduceNoTargets() {
        #expect(QuickOpenTarget.merged(favorites: [], recents: []).isEmpty)
    }

    /// Başlık kısaltılmış YOLDUR: aynı adlı iki klasör birbirinden ayırt edilebilsin ve
    /// fuzzy arama yol parçalarıyla da eşleşsin diye.
    @Test func theTitleIsTheAbbreviatedPath() {
        let target = QuickOpenTarget(path: "/Users/ahmet/Projects/pinro", kind: .recent)

        #expect(target.title(home: "/Users/ahmet") == "~/Projects/pinro")
    }

    /// Favori/son kullanılan ayrımı YALNIZ renkle anlatılmaz: ikon ve VoiceOver etiketi
    /// ayrı ayrı söyler (erişilebilirlik kuralı).
    @Test func favoriteAndRecentAreDistinguishableWithoutColor() {
        let favorite = QuickOpenTarget(path: "/Users/ahmet/p", kind: .favorite)
        let recent = QuickOpenTarget(path: "/Users/ahmet/p", kind: .recent)

        #expect(favorite.symbolName != recent.symbolName)
        #expect(favorite.accessibilityLabel(home: "/Users/ahmet") == "Favorite folder ~/p")
        #expect(recent.accessibilityLabel(home: "/Users/ahmet") == "Recent folder ~/p")
    }

    /// Palet öğe kimlikleri kalıcı listelerde saklanır; yola bağlı ve KARARLI olmalı.
    @Test func identifiersAreDerivedFromThePathAndAreStable() {
        #expect(QuickOpenTarget(path: "/a/b", kind: .recent).id == "folder./a/b")
        #expect(QuickOpenTarget(path: "/a/b", kind: .favorite).id
                == QuickOpenTarget(path: "/a/b", kind: .recent).id)
    }
}
