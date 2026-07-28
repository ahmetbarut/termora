import Foundation
import Testing
@testable import Termora

/// briefs/2 "Git Entegrasyonu": durum çubuğunda repository adı, aktif branch, değişiklik
/// durumu, ahead/behind sayısı ve son commit özeti.
///
/// En kritik iddia burada: `statusSnapshot()` 1 Hz'de çağrılıyor ve HİÇBİR git süreci
/// başlatmamalı ("Git bilgileri terminal girişini veya çıktı render işlemini
/// engellememelidir").
@MainActor
@Suite("Durum çubuğunda git detayı")
struct StatusBarGitDetailTests {

    private struct Subject {
        let workspace: WorkspaceViewModel
        let sessions: StatusStubSessionManager
        let runner: FakeGitRunner
        let repository: URL
    }

    /// `nonisolated`: aşağıda varsayılan argüman olarak okunuyor.
    private nonisolated static let statusOutput = """
        # branch.head feature/status
        # branch.upstream origin/feature/status
        # branch.ab +2 -1
        1 .M N... 100644 100644 100644 aaa bbb a.txt
        """

    /// Dosya sisteminde gerçek bir `.git` klasörü: depo ADI ve dal, git süreci
    /// ÇALIŞTIRILMADAN buradan okunuyor.
    private func makeRepository(named name: String, branch: String) throws -> URL {
        let repo = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("termora-gitbar-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/\(branch)\n"
            .write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        return repo
    }

    private func makeSubject(gitOutput: String? = statusOutput) throws -> Subject {
        let suiteName = "GitBar.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let runner = FakeGitRunner()
        if let gitOutput {
            runner.outputs[GitStatusReader.statusArguments.joined(separator: " ")] = gitOutput
            runner.outputs[GitStatusReader.lastCommitArguments.joined(separator: " ")] =
                "abc1234\u{1F}Add the status bar"
        }

        let repository = try makeRepository(named: "Termora", branch: "main")
        let sessions = StatusStubSessionManager()
        let workspace = WorkspaceViewModel(sessionManager: sessions,
                                           settings: SettingsStore(defaults: defaults),
                                           profiles: ProfileStore(defaults: defaults),
                                           gitStatus: GitStatusMonitor(runner: runner,
                                                                       minimumInterval: 0))
        workspace.newTab()
        let sessionID = try #require(workspace.activeTab?.root.leaves.first?.sessionID)
        sessions.session(id: sessionID)?.workingDirectory = repository.path
        return Subject(workspace: workspace, sessions: sessions, runner: runner, repository: repository)
    }

    // MARK: - Çizim yolu git ÇALIŞTIRMAZ

    @Test func takingASnapshotNeverRunsGit() throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.repository) }

        for _ in 0..<10 { _ = subject.workspace.statusSnapshot() }

        #expect(subject.runner.invocations.isEmpty)
    }

    /// Detay gelmeden önce çubuk yine de depo adını ve dalı gösterir: bunlar dosyadan
    /// okunuyor, süreç gerektirmiyor.
    @Test func repositoryNameAndBranchComeFromTheFilesystemBeforeAnyRefresh() throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.repository) }

        let snapshot = subject.workspace.statusSnapshot()

        #expect(snapshot?.repositoryName == "Termora")
        #expect(snapshot?.branchName == "main")
        #expect(snapshot?.gitStatus == nil)
    }

    // MARK: - Arka plan tazelemesinden sonra

    @Test func afterARefreshTheSnapshotCarriesTheFullDetail() async throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.repository) }

        await subject.workspace.refreshGitStatus()
        let snapshot = subject.workspace.statusSnapshot()

        #expect(snapshot?.gitStatus?.changedFileCount == 1)
        #expect(snapshot?.gitStatus?.ahead == 2)
        #expect(snapshot?.gitStatus?.behind == 1)
        #expect(snapshot?.gitStatus?.lastCommit?.shortHash == "abc1234")
    }

    /// git'in söylediği dal, `.git/HEAD` okumasına GALİP GELİR: dosya bayat olabilir
    /// (ör. rebase sırasında) ve git'in cevabı otoritedir.
    @Test func gitsAnswerWinsOverTheHeadFile() async throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.repository) }

        await subject.workspace.refreshGitStatus()

        #expect(subject.workspace.statusSnapshot()?.branchName == "feature/status")
    }

    /// Depo olmayan dizinde detay da dal da yoktur; uydurma bir şey gösterilmez.
    @Test func aDirectoryThatIsNotARepositoryHasNoGitInformation() async throws {
        let subject = try makeSubject(gitOutput: nil)
        defer { try? FileManager.default.removeItem(at: subject.repository) }
        let plain = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("termora-plain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        let sessionID = try #require(subject.workspace.activeTab?.root.leaves.first?.sessionID)
        subject.sessions.session(id: sessionID)?.workingDirectory = plain.path

        await subject.workspace.refreshGitStatus()
        let snapshot = subject.workspace.statusSnapshot()

        #expect(snapshot?.repositoryName == nil)
        #expect(snapshot?.branchName == nil)
        #expect(snapshot?.gitStatus == nil)
    }

    /// Aktif panel yoksa yoklama da yapılmaz.
    @Test func withoutAnActivePaneNothingIsProbed() async throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.repository) }
        subject.workspace.closeAllTabs()

        await subject.workspace.refreshGitStatus()

        #expect(subject.runner.invocations.isEmpty)
    }
}
