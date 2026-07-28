import Foundation
import Testing
@testable import Termora

/// briefs/2 "Git Entegrasyonu": dal adının yanına değişiklik durumu, ahead/behind sayısı
/// ve son commit özeti. Ayrıştırma SAFTIR — bu süitte hiçbir test `git` çalıştırmaz.
@Suite("Git durum çıktısını ayrıştırma")
struct GitStatusParsingTests {

    /// Gerçek `git status --porcelain=v2 --branch` çıktısı (upstream'i olmayan dal).
    private static let dirtyWithoutUpstream = """
        # branch.oid ea59809e57f26ee8528c651cc07c8005d363d421
        # branch.head main
        1 .M N... 100644 100644 100644 7898192261 7898192261 a.txt
        ? new.txt
        """

    private static let cleanWithUpstream = """
        # branch.oid ea59809e57f26ee8528c651cc07c8005d363d421
        # branch.head feature/status-bar
        # branch.upstream origin/feature/status-bar
        # branch.ab +2 -3
        """

    // MARK: - Dal

    @Test func readsTheBranchName() {
        let detail = GitStatusReader.detail(statusOutput: Self.cleanWithUpstream, logOutput: "")

        #expect(detail.branch == "feature/status-bar")
        #expect(detail.isDetached == false)
    }

    /// Ayrık HEAD'de git dal adı yerine `(detached)` yazar; bunu dal adı sanmak
    /// kullanıcıya var olmayan bir dal gösterirdi.
    @Test func detachedHeadIsNotABranchName() {
        let detail = GitStatusReader.detail(statusOutput: "# branch.head (detached)", logOutput: "")

        #expect(detail.branch == nil)
        #expect(detail.isDetached)
    }

    @Test func garbageOutputYieldsAnEmptyDetail() {
        let detail = GitStatusReader.detail(statusOutput: "fatal: not a git repository", logOutput: "")

        #expect(detail.branch == nil)
        #expect(detail.changedFileCount == 0)
        #expect(detail.ahead == 0)
        #expect(detail.behind == 0)
        #expect(detail.lastCommit == nil)
    }

    // MARK: - Değişiklik durumu

    @Test func countsTrackedChangesAndUntrackedFiles() {
        let detail = GitStatusReader.detail(statusOutput: Self.dirtyWithoutUpstream, logOutput: "")

        #expect(detail.changedFileCount == 2)
        #expect(detail.isDirty)
    }

    @Test func aCleanTreeHasNoChanges() {
        let detail = GitStatusReader.detail(statusOutput: Self.cleanWithUpstream, logOutput: "")

        #expect(detail.changedFileCount == 0)
        #expect(detail.isDirty == false)
    }

    /// Yoksayılan dosyalar (`!`) değişiklik DEĞİLDİR: `.gitignore`'daki build klasörü
    /// yüzünden depo sürekli "kirli" görünürdü.
    @Test func ignoredFilesAreNotChanges() {
        let output = """
            # branch.head main
            ! build/output.o
            ! .DS_Store
            """

        #expect(GitStatusReader.detail(statusOutput: output, logOutput: "").changedFileCount == 0)
    }

    /// Yeniden adlandırma (`2`) ve birleştirme çakışması (`u`) da birer değişikliktir.
    @Test func countsRenamedAndUnmergedEntries() {
        let output = """
            # branch.head main
            1 .M N... 100644 100644 100644 aaa bbb a.txt
            2 R. N... 100644 100644 100644 aaa bbb R100 new.txt\told.txt
            u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt
            ? untracked.txt
            """

        #expect(GitStatusReader.detail(statusOutput: output, logOutput: "").changedFileCount == 4)
    }

    /// `# ` ile başlayan başlık satırları ve boş satırlar sayıma girmez.
    @Test func headerLinesAreNotCountedAsChanges() {
        #expect(GitStatusReader.detail(statusOutput: Self.cleanWithUpstream,
                                       logOutput: "").changedFileCount == 0)
    }

    // MARK: - Ahead / behind

    @Test func readsAheadAndBehindCounts() {
        let detail = GitStatusReader.detail(statusOutput: Self.cleanWithUpstream, logOutput: "")

        #expect(detail.ahead == 2)
        #expect(detail.behind == 3)
        #expect(detail.hasUpstream)
    }

    /// Upstream'i olmayan dalda git `branch.ab` satırını HİÇ yazmaz. Sıfır göstermek
    /// "senkron" yalanı olurdu; bu yüzden ayrıca `hasUpstream` taşınır.
    @Test func withoutAnUpstreamThereIsNothingToCompare() {
        let detail = GitStatusReader.detail(statusOutput: Self.dirtyWithoutUpstream, logOutput: "")

        #expect(detail.hasUpstream == false)
        #expect(detail.ahead == 0)
        #expect(detail.behind == 0)
    }

    @Test func aSyncedBranchReportsZeroBothWays() {
        let output = """
            # branch.head main
            # branch.upstream origin/main
            # branch.ab +0 -0
            """
        let detail = GitStatusReader.detail(statusOutput: output, logOutput: "")

        #expect(detail.hasUpstream)
        #expect(detail.ahead == 0)
        #expect(detail.behind == 0)
    }

    // MARK: - Son commit

    @Test func readsTheLastCommitSummary() {
        let log = "ea59809\u{1F}Fix the status bar refresh"
        let detail = GitStatusReader.detail(statusOutput: Self.cleanWithUpstream, logOutput: log)

        #expect(detail.lastCommit?.shortHash == "ea59809")
        #expect(detail.lastCommit?.subject == "Fix the status bar refresh")
        #expect(detail.lastCommit?.text == "ea59809 Fix the status bar refresh")
    }

    /// Commit'i olmayan yeni depoda `git log` hiçbir şey yazmaz.
    @Test func aRepositoryWithoutCommitsHasNoSummary() {
        #expect(GitStatusReader.detail(statusOutput: Self.cleanWithUpstream, logOutput: "").lastCommit == nil)
    }

    /// Ayraç yoksa çıktı beklediğimiz biçimde değildir; uydurma bir özet yazılmaz.
    @Test func anUnexpectedLogFormatProducesNoSummary() {
        #expect(GitStatusReader.detail(statusOutput: "", logOutput: "just some text").lastCommit == nil)
    }

    /// Konusunda ayraç bulunmayan ama boşluk bulunan mesaj bozulmamalı.
    @Test func aSubjectWithSeparatorsInsideIsKeptWhole() {
        let log = "abc1234\u{1F}Add a, b and c"

        #expect(GitStatusReader.detail(statusOutput: "", logOutput: log).lastCommit?.subject
                == "Add a, b and c")
    }

    // MARK: - Komut argümanları

    /// Argümanlar sabit ve makine okunur biçimdedir; kullanıcı verisi komuta girmez.
    @Test func theCommandsAreFixedAndMachineReadable() {
        #expect(GitStatusReader.statusArguments == ["status", "--porcelain=v2", "--branch"])
        #expect(GitStatusReader.lastCommitArguments == ["log", "-1", "--pretty=format:%h%x1f%s"])
    }
}

@Suite("Git durumunun gösterimi")
struct GitStatusPresentationTests {

    private func detail(changed: Int = 0,
                        ahead: Int = 0,
                        behind: Int = 0,
                        hasUpstream: Bool = true,
                        branch: String? = "main") -> GitStatusDetail {
        GitStatusDetail(branch: branch,
                        isDetached: false,
                        changedFileCount: changed,
                        ahead: ahead,
                        behind: behind,
                        hasUpstream: hasUpstream,
                        lastCommit: GitCommitSummary(shortHash: "abc1234", subject: "Do the thing"))
    }

    /// Temiz depoda değişiklik rozeti hiç çizilmez — gürültü eklemez.
    @Test func aCleanTreeShowsNoChangeText() {
        #expect(detail(changed: 0).changesText == nil)
    }

    @Test func changeTextIsSingularForOneFile() {
        #expect(detail(changed: 1).changesText == "1 change")
        #expect(detail(changed: 4).changesText == "4 changes")
    }

    @Test func aheadAndBehindAreShownOnlyWhenTheyExist() {
        #expect(detail(ahead: 0, behind: 0).aheadBehindText == nil)
        #expect(detail(ahead: 2, behind: 0).aheadBehindText == "↑2")
        #expect(detail(ahead: 0, behind: 3).aheadBehindText == "↓3")
        #expect(detail(ahead: 2, behind: 3).aheadBehindText == "↑2 ↓3")
    }

    @Test func withoutAnUpstreamNothingIsCompared() {
        #expect(detail(ahead: 0, behind: 0, hasUpstream: false).aheadBehindText == nil)
    }

    /// brief 3 erişilebilirlik: ok işaretleri ve rozet SESLİ okunmaz; etiket her şeyi
    /// kelimelerle söyler.
    @Test func theAccessibilityLabelSpellsEverythingOut() {
        let label = detail(changed: 2, ahead: 1, behind: 3).accessibilityLabel(repositoryName: "Termora")

        #expect(label.contains("Termora"))
        #expect(label.contains("main"))
        #expect(label.contains("2 changes"))
        #expect(label.contains("1 commit ahead"))
        #expect(label.contains("3 commits behind"))
        #expect(label.contains("abc1234") || label.contains("Do the thing"))
        #expect(label.contains("↑") == false)
        #expect(label.contains("↓") == false)
    }

    @Test func aCleanSyncedRepositorySaysSoInWords() {
        let label = detail().accessibilityLabel(repositoryName: "Termora")

        #expect(label.contains("No uncommitted changes"))
    }

    @Test func detachedHeadIsAnnounced() {
        var value = detail(branch: nil)
        value.isDetached = true

        #expect(value.accessibilityLabel(repositoryName: "Termora").contains("Detached HEAD"))
    }
}
