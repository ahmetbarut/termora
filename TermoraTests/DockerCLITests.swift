import Foundation
import Testing
@testable import Termora

/// `docker` CLI'ını çalıştıran katmanın test çifti. HİÇBİR test gerçek docker çağırmaz —
/// briefs/2 entegrasyonu CLI üzerinden kurduğu için çağrının kendisi protokolün arkasındadır.
@MainActor
final class FakeDockerRunner: DockerCommandRunning {

    /// nil → bu makinede docker kurulu değil.
    var executablePath: String? = "/usr/local/bin/docker"
    /// Argüman dizisinin boşlukla birleştirilmiş hâline göre yanıt.
    var results: [String: DockerCLIResult] = [:]
    var defaultResult = DockerCLIResult(standardOutput: "", standardError: "", exitCode: 0)
    private(set) var invocations: [[String]] = []
    /// Docker'ın var olup olmadığının kaç kez sorulduğu.
    private(set) var locateCallCount = 0

    func locateExecutable() async -> String? {
        locateCallCount += 1
        return executablePath
    }

    func run(_ arguments: [String]) async -> DockerCLIResult {
        invocations.append(arguments)
        return results[arguments.joined(separator: " ")] ?? defaultResult
    }

    func stub(_ arguments: [String], output: String, exitCode: Int32 = 0, error: String = "") {
        results[arguments.joined(separator: " ")] = DockerCLIResult(standardOutput: output,
                                                                    standardError: error,
                                                                    exitCode: exitCode)
    }
}

@Suite("Docker çalıştırılabilirini bulma")
struct DockerExecutableLocatorTests {

    @Test func findsDockerOnThePathVariable() {
        let path = DockerExecutableLocator.resolve(
            pathVariable: "/usr/bin:/usr/local/bin",
            fallbackDirectories: [],
            isExecutable: { $0 == "/usr/local/bin/docker" })

        #expect(path == "/usr/local/bin/docker")
    }

    /// GUI uygulamasına verilen PATH kullanıcının kabuğundakinden dardır; Docker Desktop'ın
    /// bilinen konumları bu yüzden ayrıca denenir. Aksi hâlde kurulu docker "yok" görünürdü.
    @Test func fallsBackToKnownInstallDirectoriesWhenThePathIsThin() {
        let path = DockerExecutableLocator.resolve(
            pathVariable: "/usr/bin",
            fallbackDirectories: ["/opt/homebrew/bin"],
            isExecutable: { $0 == "/opt/homebrew/bin/docker" })

        #expect(path == "/opt/homebrew/bin/docker")
    }

    @Test func returnsNilWhenDockerIsNotInstalled() {
        #expect(DockerExecutableLocator.resolve(pathVariable: "/usr/bin:/bin",
                                                fallbackDirectories: ["/opt/homebrew/bin"],
                                                isExecutable: { _ in false }) == nil)
    }

    @Test func skipsEmptyPathEntries() {
        let path = DockerExecutableLocator.resolve(pathVariable: "::/usr/local/bin:",
                                                   fallbackDirectories: [],
                                                   isExecutable: { $0 == "/usr/local/bin/docker" })

        #expect(path == "/usr/local/bin/docker")
    }

    @Test func aNilPathVariableStillChecksTheFallbacks() {
        let path = DockerExecutableLocator.resolve(pathVariable: nil,
                                                   fallbackDirectories: ["/usr/local/bin"],
                                                   isExecutable: { $0 == "/usr/local/bin/docker" })

        #expect(path == "/usr/local/bin/docker")
    }
}

@MainActor
@Suite("DockerStore")
struct DockerStoreTests {

    private static let psOutput = """
        {"ID":"aaa111","Names":"shop-web-1","Image":"nginx","State":"running","Status":"Up 2 minutes","Labels":"com.docker.compose.project=shop,com.docker.compose.service=web,com.docker.compose.project.config_files=/s/compose.yaml"}
        {"ID":"bbb222","Names":"lonely","Image":"redis","State":"running","Status":"Up 1 hour"}
        """

    private func makeStore(_ runner: FakeDockerRunner) -> DockerStore {
        DockerStore(runner: runner)
    }

    // MARK: - Listeleme

    @Test func refreshRunsDockerPsAndParsesTheResult() async {
        let runner = FakeDockerRunner()
        runner.stub(DockerCommand.listContainers(), output: Self.psOutput)
        let store = makeStore(runner)

        await store.refresh()

        #expect(runner.invocations == [["ps", "--format", "json"]])
        #expect(store.containers.map(\.id) == ["aaa111", "bbb222"])
        #expect(store.availability == .available(path: "/usr/local/bin/docker"))
        #expect(store.lastErrorMessage == nil)
    }

    @Test func composeServicesAreDerivedFromTheContainerList() async {
        let runner = FakeDockerRunner()
        runner.stub(DockerCommand.listContainers(), output: Self.psOutput)
        let store = makeStore(runner)

        await store.refresh()

        #expect(store.composeServices.map(\.id) == ["shop/web"])
        #expect(store.composeServices.first?.configFiles == ["/s/compose.yaml"])
    }

    // MARK: - Docker kurulu değilse (dürüst davranış, çökme yok)

    @Test func withoutDockerTheStoreSaysSoAndNeverStartsAProcess() async {
        let runner = FakeDockerRunner()
        runner.executablePath = nil
        let store = makeStore(runner)

        await store.refresh()

        #expect(store.availability == .notFound)
        #expect(store.containers.isEmpty)
        #expect(store.unavailableMessage == "Docker not found")
        #expect(runner.invocations.isEmpty)
    }

    /// Kullanıcı docker'ı sonradan kurabilir: yeniden denemek yeni durumu görmeli.
    @Test func availabilityIsRecheckedOnEveryRefresh() async {
        let runner = FakeDockerRunner()
        runner.executablePath = nil
        let store = makeStore(runner)
        await store.refresh()

        runner.executablePath = "/opt/homebrew/bin/docker"
        runner.stub(DockerCommand.listContainers(), output: Self.psOutput)
        await store.refresh()

        #expect(store.availability == .available(path: "/opt/homebrew/bin/docker"))
        #expect(store.containers.count == 2)
        #expect(store.unavailableMessage == nil)
    }

    // MARK: - Hatalar

    /// Daemon kapalıysa docker sıfırdan farklı bir kodla çıkar. Mesaj KULLANICIYA
    /// aktarılır; sessizce boş liste göstermek "hiç container yok" yalanını söylerdi.
    @Test func aFailingCommandKeepsTheErrorTextAndClearsTheList() async {
        let runner = FakeDockerRunner()
        runner.stub(DockerCommand.listContainers(),
                    output: "",
                    exitCode: 1,
                    error: "Cannot connect to the Docker daemon at unix:///var/run/docker.sock.\n")
        let store = makeStore(runner)

        await store.refresh()

        #expect(store.containers.isEmpty)
        #expect(store.lastErrorMessage == "Cannot connect to the Docker daemon at unix:///var/run/docker.sock.")
    }

    @Test func aSuccessfulRefreshClearsAPreviousError() async {
        let runner = FakeDockerRunner()
        runner.stub(DockerCommand.listContainers(), output: "", exitCode: 1, error: "daemon down")
        let store = makeStore(runner)
        await store.refresh()

        runner.stub(DockerCommand.listContainers(), output: Self.psOutput)
        await store.refresh()

        #expect(store.lastErrorMessage == nil)
        #expect(store.containers.count == 2)
    }

    // MARK: - Yeniden başlatma

    /// Onay AKIŞI `WorkspaceViewModel`'de; depo yalnız onaylanmış komutu çalıştırır.
    @Test func restartRunsTheRestartCommandAndRefreshesTheList() async {
        let runner = FakeDockerRunner()
        runner.stub(DockerCommand.listContainers(), output: Self.psOutput)
        let store = makeStore(runner)
        await store.refresh()

        await store.restart(containerID: "aaa111")

        #expect(runner.invocations == [["ps", "--format", "json"],
                                       ["restart", "aaa111"],
                                       ["ps", "--format", "json"]])
    }

    @Test func aFailingRestartSurfacesTheError() async {
        let runner = FakeDockerRunner()
        runner.stub(["restart", "aaa111"], output: "", exitCode: 1, error: "No such container: aaa111")
        let store = makeStore(runner)

        await store.restart(containerID: "aaa111")

        #expect(store.lastErrorMessage == "No such container: aaa111")
    }

    // MARK: - Yükleme bir kez

    /// Palet her tuş vuruşunda `items` çağırıyor; liste EKRAN AÇILIRKEN bir kez yüklenir.
    @Test func ensureLoadedRefreshesOnlyOnce() async {
        let runner = FakeDockerRunner()
        runner.stub(DockerCommand.listContainers(), output: Self.psOutput)
        let store = makeStore(runner)

        await store.ensureLoaded()
        await store.ensureLoaded()

        #expect(runner.invocations.count == 1)
    }

    /// GERÇEK süreç yolunun tek dumanı testi: `Process` + iki boru + zaman aşımı kodu
    /// başka hiçbir testte çalışmıyor ve orada bir kilitlenme uygulamayı dondururdu.
    ///
    /// Sonuç makineye bağlı olduğu için İDDİA duruma göre kurulur: docker kurulu değilse
    /// depo dürüstçe "yok" demeli; kuruluysa çağrı ya listeyi ya da bir hata mesajı
    /// döndürmeli — her hâlükârda dönmeli ve çökmemeli.
    @Test func theRealRunnerCompletesWhetherOrNotDockerIsInstalled() async {
        let store = DockerStore(runner: DockerProcessRunner(timeout: 5))

        await store.refresh()

        if DockerExecutableLocator.resolve() == nil {
            #expect(store.availability == .notFound)
            #expect(store.unavailableMessage == "Docker not found")
        } else {
            // Çağrı DÖNDÜ (kilitlenmedi): `isRefreshing` yalnız `defer` çalıştıysa false olur.
            // Boş liste + hatasız durum da geçerlidir — hiç container çalışmıyor olabilir.
            #expect(store.availability != .notFound)
            #expect(store.isRefreshing == false)
        }
    }

    @Test func refreshStillWorksAfterEnsureLoaded() async {
        let runner = FakeDockerRunner()
        runner.stub(DockerCommand.listContainers(), output: Self.psOutput)
        let store = makeStore(runner)

        await store.ensureLoaded()
        await store.refresh()

        #expect(runner.invocations.count == 2)
    }
}
