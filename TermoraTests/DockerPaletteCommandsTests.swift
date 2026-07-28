import AppKit
import Foundation
import Testing
@testable import Termora

/// briefs/2 "Docker Entegrasyonu" işlemlerinin komut paletindeki karşılığı.
/// Container'a shell açma ve log gösterme YENİ SEKMEDE `docker` çalıştırır; yeniden
/// başlatma önce onay ister.
@MainActor
@Suite("Komut paletinde Docker kategorisi")
struct DockerPaletteCommandsTests {

    private struct Subject {
        let workspace: WorkspaceViewModel
        let sessions: MockSessionManager
        let settings: SettingsStore
        let themes: ThemeStore
        let docker: DockerStore
        let runner: FakeDockerRunner
    }

    /// `nonisolated`: varsayılan argüman ifadeleri yalıtımsız bağlamda değerlendirilir.
    nonisolated private static let psOutput = """
        {"ID":"aaa111","Names":"shop-web-1","Image":"nginx","State":"running","Status":"Up 2 minutes","Labels":"com.docker.compose.project=shop,com.docker.compose.service=web,com.docker.compose.project.config_files=/s/compose.yaml"}
        {"ID":"bbb222","Names":"lonely","Image":"redis","State":"running","Status":"Up 1 hour"}
        """

    private func makeSubject(psOutput: String = psOutput,
                             executablePath: String? = "/usr/local/bin/docker") async throws -> Subject {
        let suiteName = "DockerPalette.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let runner = FakeDockerRunner()
        runner.executablePath = executablePath
        runner.stub(DockerCommand.listContainers(), output: psOutput)
        let docker = DockerStore(runner: runner)
        await docker.refresh()

        let sessions = MockSessionManager()
        let settings = SettingsStore(defaults: defaults)
        let workspace = WorkspaceViewModel(sessionManager: sessions,
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()
        return Subject(workspace: workspace,
                       sessions: sessions,
                       settings: settings,
                       themes: ThemeStore(bundle: .main),
                       docker: docker,
                       runner: runner)
    }

    private func items(_ subject: Subject, docker: DockerStore?) -> [CommandPaletteItem] {
        CommandPaletteCatalog.items(workspace: subject.workspace,
                                    settings: subject.settings,
                                    themes: subject.themes,
                                    docker: docker,
                                    openSettings: {})
    }

    private func dockerItems(_ subject: Subject) -> [CommandPaletteItem] {
        items(subject, docker: subject.docker).filter { $0.category == .docker }
    }

    private func item(_ id: String, in subject: Subject) throws -> CommandPaletteItem {
        try #require(dockerItems(subject).first { $0.id == id })
    }

    // MARK: - Listeleme

    /// Depo bağlı değilse (Docker'ı hiç kullanmayan bağlamlar) kategori hiç çizilmez.
    @Test func withoutAStoreThereIsNoDockerCategory() async throws {
        let subject = try await makeSubject()
        #expect(items(subject, docker: nil).contains { $0.category == .docker } == false)
    }

    /// Hiç container çalışmıyorsa boş bir "Docker" başlığı görünmemeli.
    @Test func withNoRunningContainersTheCategoryIsEmpty() async throws {
        let subject = try await makeSubject(psOutput: "")
        #expect(dockerItems(subject).isEmpty)
    }

    /// briefs/2: çalışan container'ları listeleme + shell açma + log + yeniden başlatma.
    @Test func everyRunningContainerGetsShellLogsAndRestart() async throws {
        let subject = try await makeSubject()
        let ids = dockerItems(subject).map(\.id)

        #expect(ids.contains("docker.shell.aaa111"))
        #expect(ids.contains("docker.logs.aaa111"))
        #expect(ids.contains("docker.restart.aaa111"))
        #expect(ids.contains("docker.shell.bbb222"))
    }

    /// briefs/2 "Docker Compose servislerini listeleme" + "bir servis için compose exec".
    @Test func everyComposeServiceGetsAnExecCommand() async throws {
        let subject = try await makeSubject()

        #expect(dockerItems(subject).map(\.id).contains("docker.compose.shell.shop/web"))
    }

    /// Çalışmayan container listelenmez: onun içine shell açılamaz.
    @Test func stoppedContainersAreNotListed() async throws {
        let subject = try await makeSubject(
            psOutput: #"{"ID":"ccc333","Names":"old","State":"exited","Status":"Exited (0)"}"#)

        #expect(dockerItems(subject).isEmpty)
    }

    @Test func titlesNameTheContainerAndTheAction() async throws {
        let subject = try await makeSubject()

        #expect(try item("docker.shell.aaa111", in: subject).title == "Open Shell in “shop-web-1”")
        #expect(try item("docker.logs.aaa111", in: subject).title == "Show Logs for “shop-web-1”")
        #expect(try item("docker.restart.aaa111", in: subject).title == "Restart “shop-web-1”…")
        #expect(try item("docker.compose.shell.shop/web", in: subject).title
                == "Open Shell in Service “shop / web”")
    }

    @Test func everyDockerCommandHasAUniqueIdentifierAndAResolvableSymbol() async throws {
        let subject = try await makeSubject()
        let all = items(subject, docker: subject.docker)

        #expect(Set(all.map(\.id)).count == all.count)
        for item in dockerItems(subject) {
            #expect(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) != nil,
                    "\(item.id) SF Symbol'ü yok: \(item.symbolName)")
            #expect(item.accessibilityLabel.isEmpty == false)
        }
    }

    @Test func dockerIsListedAfterFoldersAndBeforeSettings() async throws {
        let subject = try await makeSubject()
        let categories = items(subject, docker: subject.docker).map(\.category)
        let firstDocker = try #require(categories.firstIndex(of: .docker))
        let firstSettings = try #require(categories.firstIndex(of: .settings))

        #expect(firstDocker < firstSettings)
        #expect(CommandPaletteCategory.docker.title == "Docker")
    }

    // MARK: - Docker kurulu değilse

    /// Brief: kurulu değilse özellik DÜRÜSTÇE söylesin, çökmesin. Tek bir satır kalır ve
    /// o satır bir eylem adlandırır (yeniden kontrol), ölü bir satır değildir.
    @Test func withoutDockerASingleHonestRowExplainsWhy() async throws {
        let subject = try await makeSubject(executablePath: nil)
        let rows = dockerItems(subject)

        #expect(rows.map(\.id) == ["docker.unavailable"])
        #expect(rows.first?.title == "Docker Not Found — Check Again")
        #expect(rows.first?.accessibilityLabel.contains("Docker") == true)
    }

    /// Kullanıcı bu arada Docker'ı kurmuş olabilir: satır varlığı YENİDEN sorar.
    @Test func theUnavailableRowRechecksInsteadOfDoingNothing() async throws {
        let subject = try await makeSubject(executablePath: nil)
        let before = subject.runner.locateCallCount
        subject.runner.executablePath = "/usr/local/bin/docker"

        try item("docker.unavailable", in: subject).action()
        // Eylem arka planda çalışıyor; kontrolün tamamlanmasını bekle.
        while subject.runner.locateCallCount == before { await Task.yield() }
        while subject.docker.isRefreshing { await Task.yield() }

        #expect(subject.runner.locateCallCount > before)
        #expect(subject.docker.availability == .available(path: "/usr/local/bin/docker"))
        #expect(subject.docker.containers.count == 2)
    }

    // MARK: - Shell ve loglar yeni sekmede

    @Test func openingAShellRunsDockerExecInANewTab() async throws {
        let subject = try await makeSubject()
        let tabsBefore = subject.workspace.tabs.count

        try item("docker.shell.aaa111", in: subject).action()

        #expect(subject.workspace.tabs.count == tabsBefore + 1)
        #expect(subject.sessions.createdStartupCommands.last
                == "/usr/local/bin/docker exec -it aaa111 /bin/sh")
    }

    @Test func showingLogsFollowsABoundedBacklogInANewTab() async throws {
        let subject = try await makeSubject()

        try item("docker.logs.aaa111", in: subject).action()

        #expect(subject.sessions.createdStartupCommands.last
                == "/usr/local/bin/docker logs --tail 200 --follow aaa111")
    }

    @Test func composeExecPassesTheConfigFileAndProject() async throws {
        let subject = try await makeSubject()

        try item("docker.compose.shell.shop/web", in: subject).action()

        #expect(subject.sessions.createdStartupCommands.last
                == "/usr/local/bin/docker compose -f /s/compose.yaml -p shop exec web /bin/sh")
    }

    /// Açık sekmeler kapanmaz: container'a bağlanmak pencereyi sıfırlayan bir işlem değildir.
    @Test func openingAShellLeavesTheOpenTabsAlone() async throws {
        let subject = try await makeSubject()

        try item("docker.shell.aaa111", in: subject).action()

        #expect(subject.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test func theNewTabIsNamedAfterTheContainer() async throws {
        let subject = try await makeSubject()

        try item("docker.shell.aaa111", in: subject).action()

        #expect(subject.workspace.activeTab?.displayTitle == "shop-web-1")
    }

    /// Düşmanca bir container adı komutu BÖLEMEZ. Komut her zaman KİMLİKLE kurulur ve
    /// ad yalnız başlıkta görünür; yine de alıntılama sınamada tutulur.
    @Test func aHostileContainerNameNeverReachesTheCommand() async throws {
        let subject = try await makeSubject(
            psOutput: #"{"ID":"ddd444","Names":"evil; rm -rf ~","State":"running"}"#)

        try item("docker.shell.ddd444", in: subject).action()

        #expect(subject.sessions.createdStartupCommands.last
                == "/usr/local/bin/docker exec -it ddd444 /bin/sh")
    }

    // MARK: - Yeniden başlatma önce sorar

    /// briefs/2 onay kuralı: palet satırı komutu ÇALIŞTIRMAZ, onay ister.
    @Test func restartAsksBeforeRunningAnything() async throws {
        let subject = try await makeSubject()
        let before = subject.runner.invocations.count

        try item("docker.restart.aaa111", in: subject).action()

        #expect(subject.workspace.pendingDockerAction != nil)
        #expect(subject.workspace.pendingDockerActionTitle.contains("shop-web-1"))
        #expect(subject.runner.invocations.count == before)
    }

    @Test func confirmingTheRestartRunsTheDockerCommand() async throws {
        let subject = try await makeSubject()
        try item("docker.restart.aaa111", in: subject).action()

        subject.workspace.confirmPendingDockerAction()
        // Yeniden başlatma arka planda çalışıyor; bitmesini bekle.
        while subject.runner.invocations.contains(["restart", "aaa111"]) == false {
            await Task.yield()
        }

        #expect(subject.runner.invocations.contains(["restart", "aaa111"]))
    }

    @Test func cancellingTheRestartRunsNothing() async throws {
        let subject = try await makeSubject()
        let before = subject.runner.invocations.count
        try item("docker.restart.aaa111", in: subject).action()

        subject.workspace.cancelPendingDockerAction()
        await Task.yield()

        #expect(subject.runner.invocations.count == before)
    }
}
