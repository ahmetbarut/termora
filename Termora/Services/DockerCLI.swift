import Darwin
import Foundation
import Observation
import os

/// Bir dış komutun sonucu.
nonisolated struct ExternalCommandResult: Equatable, Sendable {
    var standardOutput: String
    var standardError: String
    var exitCode: Int32

    var isSuccess: Bool { exitCode == 0 }
}

/// `docker` çağrısının sonucu; tip dış komutlarla ortaktır.
typealias DockerCLIResult = ExternalCommandResult

/// Dış bir komutu çalıştırmanın TEK kopyası. `DockerProcessRunner` ve
/// `GitProcessRunner` ikisi de buradan geçer — süreç yönetiminin ince yerleri
/// (boru kilitlenmesi, zaman aşımı) iki yerde ayrı ayrı doğrulanamaz.
nonisolated enum ExternalCommand {

    private static let queue = DispatchQueue(label: "com.ahmetbarut.Termora.external-command",
                                             qos: .utility,
                                             attributes: .concurrent)

    /// Komutu ARKA PLANDA çalıştırır; çağıran aktör bloke olmaz, yalnız askıya alınır.
    static func run(executablePath: String,
                    arguments: [String],
                    currentDirectory: String? = nil,
                    environment: [String: String]? = nil,
                    timeout: TimeInterval) async -> ExternalCommandResult {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: execute(executablePath: executablePath,
                                                       arguments: arguments,
                                                       currentDirectory: currentDirectory,
                                                       environment: environment,
                                                       timeout: timeout))
            }
        }
    }

    /// İki boruyu AYNI ANDA boşaltır: biri dolup bloke olursa süreç asla bitmez
    /// (borular 64 KB'de dolar ve `waitUntilExit` sonsuza kadar bekler).
    private static func execute(executablePath: String,
                                arguments: [String],
                                currentDirectory: String?,
                                environment: [String: String]?,
                                timeout: TimeInterval) -> ExternalCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        }
        if let environment {
            process.environment = environment
        }
        let outPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return ExternalCommandResult(standardOutput: "",
                                         standardError: error.localizedDescription,
                                         exitCode: -1)
        }

        let errorBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        queue.async {
            errorBox.value = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        // Kilitlenmiş bir daemon ya da ağ dosya sistemi uygulamayı süresiz bekletemez.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()

        return ExternalCommandResult(standardOutput: String(decoding: outData, as: UTF8.self),
                                     standardError: String(decoding: errorBox.value, as: UTF8.self),
                                     exitCode: process.terminationStatus)
    }

    /// Kuyruklar arası tek yazar / tek okuyucu aktarımı; `group.wait()` sıralamayı garanti eder.
    private final class DataBox: @unchecked Sendable {
        var value = Data()
    }
}

/// `docker` CLI çağrılarının TEK kapısı (briefs/2: daemon ile karmaşık bir API
/// entegrasyonu yerine başlangıçta CLI komutları).
///
/// Protokol arkasına alınmasının sebebi testtir: testler sahte çıktı verir ve bu makinede
/// docker kurulu olsun ya da olmasın hiçbir süreç başlatılmaz.
///
/// İki üye de `async`'tir. Gerçek uygulama süreci ARKA PLANDA çalıştırır; ana aktör
/// yalnız askıya alınır, bloke olmaz — terminal girişi ve çizim durmaz.
protocol DockerCommandRunning {
    /// Docker çalıştırılabilirinin tam yolu; kurulu değilse nil. Süreç başlatmaz.
    func locateExecutable() async -> String?
    func run(_ arguments: [String]) async -> DockerCLIResult
}

// MARK: - Docker'ı bulma

/// `which docker`ın süreç başlatmayan karşılığı: PATH taranır, sonra Docker Desktop'ın
/// bilinen kurulum dizinleri denenir.
///
/// Bilinen dizinlerin ayrıca denenmesi şart: bir GUI uygulamasına verilen PATH,
/// kullanıcının kabuğundakinden çok dardır (`launchd` varsayılanı genelde
/// `/usr/bin:/bin:/usr/sbin:/sbin`) ve Docker Desktop kendini `/usr/local/bin` ya da
/// `~/.docker/bin` altına kurar. Yalnız PATH'e bakan bir kontrol kurulu docker'ı
/// "yok" diye raporlardı.
nonisolated enum DockerExecutableLocator {

    static func defaultFallbackDirectories(home: String = NSHomeDirectory()) -> [String] {
        ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", home + "/.docker/bin"]
    }

    /// Test dikişli saf çekirdek.
    static func resolve(pathVariable: String?,
                        fallbackDirectories: [String],
                        isExecutable: (String) -> Bool) -> String? {
        let fromPath = (pathVariable ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        for directory in fromPath + fallbackDirectories {
            let candidate = (directory as NSString).appendingPathComponent("docker")
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// Gerçek dosya sisteminden okuyan sarmalayıcı.
    ///
    /// `Darwin.access`: proje kuralı — `access` başka bağlamlarda gölgelenebiliyor.
    static func resolve() -> String? {
        resolve(pathVariable: ProcessInfo.processInfo.environment["PATH"],
                fallbackDirectories: defaultFallbackDirectories(),
                isExecutable: { Darwin.access($0, X_OK) == 0 })
    }
}

// MARK: - Gerçek çalıştırıcı

/// `docker` sürecini arka plan kuyruğunda çalıştırır.
@MainActor
final class DockerProcessRunner: DockerCommandRunning {

    /// Kilitlenmiş bir daemon uygulamayı süresiz bekletemez: süre dolunca süreç sonlandırılır.
    private let timeout: TimeInterval

    /// Çözülen yol önbelleğe ALINMAZ: kullanıcı Docker'ı uygulama açıkken kurabilir
    /// ve `access` çağrısı zaten mikrosaniyeler sürüyor.
    init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    func locateExecutable() async -> String? {
        DockerExecutableLocator.resolve()
    }

    func run(_ arguments: [String]) async -> DockerCLIResult {
        guard let path = DockerExecutableLocator.resolve() else {
            return DockerCLIResult(standardOutput: "", standardError: "Docker not found", exitCode: -1)
        }
        return await ExternalCommand.run(executablePath: path, arguments: arguments, timeout: timeout)
    }
}

// MARK: - Depo

/// Çalışan container'ların ve compose servislerinin gözlemlenebilir listesi.
///
/// MALİYET: tek bir `docker ps --format json` çağrısı bu makinede ~20 ms sürüyor ve
/// arka planda çalışıyor. Liste bu yüzden ZAMANLAYICIYLA yenilenmez — ekran açılırken
/// bir kez (`ensureLoaded`) ve kullanıcı bir işlem yaptığında (`restart`) tazelenir.
/// Compose servisleri aynı çıktının etiketlerinden türetilir, ikinci bir süreç yoktur.
@MainActor
@Observable
final class DockerStore {

    enum Availability: Equatable, Sendable {
        case unknown
        case available(path: String)
        case notFound
    }

    /// Docker bulunamadığında kullanıcıya gösterilecek dürüst metin (brief: çökme yok).
    static let notFoundMessage = "Docker not found"

    private(set) var availability: Availability = .unknown
    private(set) var containers: [DockerContainer] = []
    /// Son başarısız çağrının mesajı; başarılı çağrı temizler.
    private(set) var lastErrorMessage: String?
    private(set) var hasLoaded = false

    /// SAYAÇ, bayrak değil: `refresh()` yeniden girilebilir (kullanıcı iki kez
    /// tetikleyebilir) ve tek bir `Bool`'da ilk bitişin `defer`'i, hâlâ çalışan ikinci
    /// tazelemeyi "bitti" gösterirdi.
    private(set) var activeRefreshCount = 0

    var isRefreshing: Bool { activeRefreshCount > 0 }

    private let runner: any DockerCommandRunning
    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "DockerStore")

    /// Nesne grafiğinin kökü `AppServices`'tir; oraya bağlanana kadar paylaşılan örnek
    /// paletle uygulamanın geri kalanının AYNI listeyi görmesini sağlar (`SSHHostStore`
    /// ile aynı dikiş). Testler her zaman kendi sahte çalıştırıcılarıyla kendi deposunu kurar.
    static let shared = DockerStore()

    /// `runner` varsayılanı init'in İÇİNDE kurulur: varsayılan argüman ifadeleri
    /// yalıtımsız (nonisolated) bağlamda değerlendirilir ve `DockerProcessRunner`
    /// `MainActor`'a bağlıdır.
    init(runner: (any DockerCommandRunning)? = nil) {
        self.runner = runner ?? DockerProcessRunner()
    }

    /// Container'ların hangi compose servisine ait olduğu; ek süreç yoktur.
    var composeServices: [DockerComposeService] {
        DockerComposeService.services(in: containers)
    }

    var executablePath: String? {
        if case let .available(path) = availability { return path }
        return nil
    }

    var unavailableMessage: String? {
        availability == .notFound ? Self.notFoundMessage : nil
    }

    /// Ekran açılışında çağrılır; listeyi bir KEZ yükler.
    func ensureLoaded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    /// Listeyi tazeler. Docker kurulu değilse hiçbir süreç başlatılmaz.
    func refresh() async {
        hasLoaded = true
        activeRefreshCount += 1
        defer { activeRefreshCount -= 1 }

        guard let path = await runner.locateExecutable() else {
            availability = .notFound
            containers = []
            return
        }
        availability = .available(path: path)

        let result = await runner.run(DockerCommand.listContainers())
        guard result.isSuccess else {
            containers = []
            lastErrorMessage = Self.message(from: result)
            Self.logger.error("docker ps failed with exit code \(result.exitCode, privacy: .public)")
            return
        }
        lastErrorMessage = nil
        containers = DockerContainerParser.containers(from: result.standardOutput)
    }

    /// Container'ı yeniden başlatır ve listeyi tazeler.
    ///
    /// ONAY BURADA SORULMAZ: brief "yeniden başlatma gibi etkili işlemlerde kullanıcıdan
    /// onay alınmalıdır" diyor ve o akış `WorkspaceViewModel.requestDockerAction`'da
    /// duruyor. Bu metoda YALNIZ onaydan sonra gelinir.
    func restart(containerID: String) async {
        let result = await runner.run(DockerCommand.restart(containerID: containerID))
        guard result.isSuccess else {
            lastErrorMessage = Self.message(from: result)
            return
        }
        lastErrorMessage = nil
        await refresh()
    }

    /// Hata metni: docker mesajı stderr'e yazar, boşsa çıkış kodu bildirilir.
    /// Uydurma bir açıklama yazılmaz.
    private static func message(from result: DockerCLIResult) -> String {
        let text = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty { return output }
        return "docker exited with code \(result.exitCode)"
    }
}
