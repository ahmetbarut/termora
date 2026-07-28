import Foundation
import Testing
@testable import Termora

/// briefs/2: "Git bilgileri terminal girişini veya çıktı render işlemini ENGELLEMEMELİDİR.
/// Kontroller arka planda ve KONTROLLÜ ARALIKLARLA yapılmalıdır."
///
/// Bu süit tam olarak o iki cümleyi sınar: okuma önbellekten yapılır (asla süreç
/// başlatmaz) ve tazeleme en fazla belirli aralıklarla çalışır.
@MainActor
final class FakeGitRunner: GitCommandRunning {

    /// Argüman dizisine göre yanıt; yoksa `defaultOutput`.
    var outputs: [String: String] = [:]
    var defaultOutput: String?
    private(set) var invocations: [(arguments: [String], directory: String)] = []

    func run(_ arguments: [String], in directory: String) async -> String? {
        invocations.append((arguments, directory))
        // Gerçek çalıştırıcı gibi ASKIYA ALIR: çakışan tazelemelerin iç içe geçtiği
        // durumu ancak burada bir askı noktası varsa sınayabiliriz.
        await Task.yield()
        return outputs[arguments.joined(separator: " ")] ?? defaultOutput
    }

    var directoriesQueried: [String] {
        invocations.map(\.directory)
    }

    /// `status` çağrısı sayısı — bir tazeleme turunda tam bir tane olmalı.
    var statusCallCount: Int {
        invocations.filter { $0.arguments == GitStatusReader.statusArguments }.count
    }
}

@MainActor
@Suite("GitStatusMonitor")
struct GitStatusMonitorTests {

    private static let statusOutput = """
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +1 -0
        ? new.txt
        """

    private func makeMonitor(interval: TimeInterval = 5) -> (GitStatusMonitor, FakeGitRunner) {
        let runner = FakeGitRunner()
        runner.outputs[GitStatusReader.statusArguments.joined(separator: " ")] = Self.statusOutput
        runner.outputs[GitStatusReader.lastCommitArguments.joined(separator: " ")] =
            "abc1234\u{1F}Add the status bar"
        return (GitStatusMonitor(runner: runner, minimumInterval: interval), runner)
    }

    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Okuma asla süreç başlatmaz

    /// Durum çubuğu 1 Hz'de ÇİZİM yaparken bu değeri okuyor; okumanın maliyeti sıfır olmalı.
    @Test func readingTheCachedStatusNeverRunsGit() async {
        let (monitor, runner) = makeMonitor()

        _ = monitor.status(forDirectory: "/repo")

        #expect(runner.invocations.isEmpty)
    }

    @Test func theCacheIsFilledByARefresh() async {
        let (monitor, _) = makeMonitor()

        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start)

        let status = monitor.status(forDirectory: "/repo")
        #expect(status?.branch == "main")
        #expect(status?.changedFileCount == 1)
        #expect(status?.ahead == 1)
        #expect(status?.lastCommit?.shortHash == "abc1234")
    }

    /// Önbellek DİZİNE bağlıdır: başka bir panelin dizini sorulduğunda önceki deponun
    /// sayıları döndürülmemeli.
    @Test func theCacheIsNotHandedOutForADifferentDirectory() async {
        let (monitor, _) = makeMonitor()
        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start)

        #expect(monitor.status(forDirectory: "/somewhere/else") == nil)
    }

    // MARK: - Kontrollü aralık

    @Test func aSecondCallWithinTheIntervalDoesNotRunGitAgain() async {
        let (monitor, runner) = makeMonitor(interval: 5)

        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start)
        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start.addingTimeInterval(1))
        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start.addingTimeInterval(4.9))

        #expect(runner.statusCallCount == 1)
    }

    @Test func afterTheIntervalItRunsAgain() async {
        let (monitor, runner) = makeMonitor(interval: 5)

        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start)
        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start.addingTimeInterval(5))

        #expect(runner.statusCallCount == 2)
    }

    /// Aralık, durum çubuğunun 1 Hz bütçesinden AYRIDIR: git çağrısı ~20 ms sürüyor ve
    /// her saniye çalıştırılamaz.
    @Test func theDefaultIntervalIsWellAboveTheStatusBarTick() {
        #expect(GitStatusMonitor.defaultMinimumInterval >= 5)
    }

    /// Kullanıcı `cd` yaptığında beklemek yanlış deponun bilgisini ekranda tutar.
    @Test func changingDirectoryRefreshesImmediately() async {
        let (monitor, runner) = makeMonitor(interval: 5)
        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start)

        await monitor.refreshIfNeeded(directory: "/other", now: Self.start.addingTimeInterval(0.1))

        #expect(runner.statusCallCount == 2)
        #expect(runner.directoriesQueried.last == "/other")
    }

    /// Dizin değiştiği ANDA eski deponun sayıları düşer; yeni sonuç gelene kadar
    /// yanlış bir dal/sayı göstermek yalan olurdu.
    @Test func aStaleResultIsNotShownForTheNewDirectory() async {
        let (monitor, runner) = makeMonitor()
        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start)
        runner.outputs.removeAll()
        runner.defaultOutput = nil

        await monitor.refreshIfNeeded(directory: "/other", now: Self.start.addingTimeInterval(0.1))

        #expect(monitor.status(forDirectory: "/other") == nil)
        #expect(monitor.status(forDirectory: "/repo") == nil)
    }

    // MARK: - Depo olmayan dizin

    @Test func aDirectoryThatIsNotARepositoryHasNoStatus() async {
        let runner = FakeGitRunner()
        runner.defaultOutput = nil
        let monitor = GitStatusMonitor(runner: runner, minimumInterval: 5)

        await monitor.refreshIfNeeded(directory: "/tmp", now: Self.start)

        #expect(monitor.status(forDirectory: "/tmp") == nil)
    }

    @Test func aNilDirectoryClearsTheStatusAndRunsNothing() async {
        let (monitor, runner) = makeMonitor()
        await monitor.refreshIfNeeded(directory: "/repo", now: Self.start)
        let before = runner.invocations.count

        await monitor.refreshIfNeeded(directory: nil, now: Self.start.addingTimeInterval(10))

        #expect(monitor.status(forDirectory: "/repo") == nil)
        #expect(runner.invocations.count == before)
    }

    // MARK: - Aynı anda tek çalışma

    /// Yavaş bir depoda çakışan tazelemeler git süreçlerini üst üste bindirirdi.
    @Test func overlappingRefreshesRunTheCommandsOnce() async {
        let (monitor, runner) = makeMonitor(interval: 0)

        async let first: Void = monitor.refreshIfNeeded(directory: "/repo", now: Self.start)
        async let second: Void = monitor.refreshIfNeeded(directory: "/repo", now: Self.start)
        _ = await (first, second)

        #expect(runner.statusCallCount == 1)
    }

    // MARK: - Gerçek git süreci

    /// `GIT_OPTIONAL_LOCks=0`: `git status` normalde index kilidi alır ve kullanıcının
    /// terminalde çalıştırdığı git komutuyla ÇAKIŞIR. Termora arka planda yoklama
    /// yaptığı için bu bayrak şart (briefs/2 "engellememelidir").
    @Test func theRealRunnerNeverTakesTheIndexLock() {
        #expect(GitProcessRunner.environment["GIT_OPTIONAL_LOCKS"] == "0")
    }
}
