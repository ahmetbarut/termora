import Foundation
import Observation

/// Son commit'in kısa özeti (briefs/2 "Son commit özeti").
nonisolated struct GitCommitSummary: Equatable, Sendable {
    var shortHash: String
    var subject: String

    var text: String { "\(shortHash) \(subject)" }
}

/// briefs/2 "Git Entegrasyonu"nun istediği bağlamsal bilgiler: aktif dal, değişiklik
/// durumu, ahead/behind sayısı ve son commit özeti.
///
/// Depo ADI burada DEĞİLDİR: onu `GitRepositoryReader` dosya sisteminden okuyor ve bir
/// git süreci gerektirmiyor. Bu yapı yalnız git'in ÇIKTISINDA yazan şeyleri taşır.
///
/// briefs/2 sınırı: "Termora bir Git istemcisine dönüştürülmemelidir." Burada hiçbir
/// yazma işlemi yok — okunan bilgi yalnız durum çubuğunda gösteriliyor.
nonisolated struct GitStatusDetail: Equatable, Sendable {
    /// Dal adı; ayrık HEAD'de nil.
    var branch: String?
    var isDetached: Bool
    /// Takip edilen değişiklikler + izlenmeyen dosyalar. Yoksayılanlar (`!`) sayılmaz.
    var changedFileCount: Int
    var ahead: Int
    var behind: Int
    /// Dalın bir upstream'i var mı? Yoksa ahead/behind KARŞILAŞTIRILAMAZ; sıfır göstermek
    /// "senkron" yalanı olurdu.
    var hasUpstream: Bool
    var lastCommit: GitCommitSummary?

    var isDirty: Bool { changedFileCount > 0 }

    /// Durum çubuğundaki değişiklik rozeti; temiz depoda hiç çizilmez.
    /// Rozet METİNDİR — brief 3 "durum yalnız renkle anlatılmasın".
    var changesText: String? {
        guard changedFileCount > 0 else { return nil }
        return changedFileCount == 1 ? "1 change" : "\(changedFileCount) changes"
    }

    /// "↑2 ↓3". Upstream yoksa ya da iki taraf da sıfırsa nil.
    var aheadBehindText: String? {
        guard hasUpstream else { return nil }
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// VoiceOver metni: ok işaretleri ve rozetler SESLİ OKUNMAZ, bu yüzden her şey
    /// kelimelerle tekrar edilir (brief 3 erişilebilirlik).
    func accessibilityLabel(repositoryName: String?) -> String {
        var parts: [String] = []
        if let repositoryName { parts.append("Repository \(repositoryName)") }
        if isDetached {
            parts.append("Detached HEAD")
        } else if let branch {
            parts.append("Branch \(branch)")
        }
        parts.append(changesText ?? "No uncommitted changes")
        if hasUpstream {
            if ahead > 0 { parts.append("\(ahead) commit\(ahead == 1 ? "" : "s") ahead") }
            if behind > 0 { parts.append("\(behind) commit\(behind == 1 ? "" : "s") behind") }
            if ahead == 0, behind == 0 { parts.append("Up to date with the upstream branch") }
        } else {
            parts.append("No upstream branch")
        }
        if let lastCommit { parts.append("Last commit \(lastCommit.text)") }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - Ayrıştırma

/// `git status --porcelain=v2 --branch` ve `git log -1` çıktılarını okuyan SAF çekirdek.
///
/// `--porcelain=v2` bilinçli bir seçim: bu biçim git tarafından "kararlı" ilan edilmiştir
/// (insan okunur çıktı sürümden sürüme değişir ve kullanıcının `status.*` ayarlarından
/// etkilenir).
nonisolated enum GitStatusReader {

    static let statusArguments = ["status", "--porcelain=v2", "--branch"]
    /// `%x1f` = ASCII Unit Separator: commit konusu boşluk da içerebildiği için
    /// hash ile konu arasında metinde ASLA geçmeyecek bir ayraç kullanılır.
    static let lastCommitArguments = ["log", "-1", "--pretty=format:%h%x1f%s"]

    private static let detachedHead = "(detached)"

    static func detail(statusOutput: String, logOutput: String) -> GitStatusDetail {
        var branch: String?
        var isDetached = false
        var changed = 0
        var ahead = 0
        var behind = 0
        var hasUpstream = false

        for rawLine in statusOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if let head = value(after: "# branch.head ", in: line) {
                if head == detachedHead {
                    isDetached = true
                } else {
                    branch = head
                }
            } else if value(after: "# branch.upstream ", in: line) != nil {
                hasUpstream = true
            } else if let ab = value(after: "# branch.ab ", in: line) {
                hasUpstream = true
                (ahead, behind) = aheadBehind(in: ab)
            } else if line.hasPrefix("# ") {
                continue
            } else if isChangeEntry(line) {
                changed += 1
            }
        }

        return GitStatusDetail(branch: branch,
                               isDetached: isDetached,
                               changedFileCount: changed,
                               ahead: ahead,
                               behind: behind,
                               hasUpstream: hasUpstream,
                               lastCommit: commitSummary(logOutput: logOutput))
    }

    /// porcelain v2 girdi satırları: `1` değişmiş, `2` yeniden adlandırılmış,
    /// `u` birleştirme çakışması, `?` izlenmeyen. `!` YOKSAYILAN dosyadır ve bir
    /// değişiklik DEĞİLDİR — `.gitignore`'daki build klasörü yüzünden her depo
    /// sürekli "kirli" görünürdü.
    private static func isChangeEntry(_ line: String) -> Bool {
        guard line.count >= 2 else { return false }
        let marker = line.prefix(1)
        guard ["1", "2", "u", "?"].contains(String(marker)) else { return false }
        return line.dropFirst().hasPrefix(" ")
    }

    /// "+2 -3" → (2, 3). Beklenmedik biçimde sıfır döner; uydurma sayı yazılmaz.
    private static func aheadBehind(in text: String) -> (Int, Int) {
        var ahead = 0
        var behind = 0
        for token in text.split(separator: " ") {
            let number = Int(token.dropFirst()) ?? 0
            if token.hasPrefix("+") { ahead = number }
            if token.hasPrefix("-") { behind = number }
        }
        return (ahead, behind)
    }

    private static func commitSummary(logOutput: String) -> GitCommitSummary? {
        guard let line = logOutput.split(separator: "\n").first else { return nil }
        let parts = line.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let hash = parts[0].trimmingCharacters(in: .whitespaces)
        let subject = parts[1].trimmingCharacters(in: .whitespaces)
        guard !hash.isEmpty else { return nil }
        return GitCommitSummary(shortHash: hash, subject: subject)
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

// MARK: - git çalıştırma

/// `git` çağrılarının TEK kapısı. Protokol arkasında olmasının sebebi testtir: testler
/// sahte çıktı verir ve gerçek bir depo kurmak zorunda kalmaz.
protocol GitCommandRunning {
    /// Komut başarılıysa stdout; depo değilse ya da komut başarısızsa nil.
    func run(_ arguments: [String], in directory: String) async -> String?
}

@MainActor
final class GitProcessRunner: GitCommandRunning {

    static let executablePath = "/usr/bin/git"

    /// KRİTİK: `GIT_OPTIONAL_LOCKS=0`. `git status` normalde index'i tazeler ve
    /// `.git/index.lock` alır; Termora bunu arka planda saniyede bir yapsaydı
    /// kullanıcının terminalde çalıştırdığı `git commit` "unable to create index.lock"
    /// ile patlardı. briefs/2: "Git bilgileri terminal girişini … engellememelidir."
    ///
    /// `GIT_TERMINAL_PROMPT=0`: yoklama hiçbir koşulda kimlik sormaz — soran bir süreç
    /// zaman aşımına kadar asılı kalırdı.
    nonisolated static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        return environment
    }

    private let timeout: TimeInterval

    init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    func run(_ arguments: [String], in directory: String) async -> String? {
        let result = await ExternalCommand.run(executablePath: Self.executablePath,
                                               arguments: arguments,
                                               currentDirectory: directory,
                                               environment: Self.environment,
                                               timeout: timeout)
        guard result.isSuccess else { return nil }
        return result.standardOutput
    }
}

// MARK: - Kontrollü aralıklı yoklama

/// Aktif panelin dizini için git durumunu ARKA PLANDA ve KONTROLLÜ ARALIKLARLA tazeler
/// (briefs/2: "Git bilgileri terminal girişini veya çıktı render işlemini
/// engellememelidir").
///
/// ÖLÇÜM: `git status --porcelain=v2 --branch` + `git log -1` bu depoda birlikte ~20-30 ms
/// sürüyor. Durum çubuğu 1 Hz'de yenileniyor ve bir kare 16.6 ms; yani bu çağrıyı o
/// bütçenin İÇİNE koymak her saniye bir kare düşürürdü. Bu yüzden iki ayrım var:
///
/// 1. **Okuma bedavadır.** `status(forDirectory:)` yalnız önbelleği verir, asla süreç
///    başlatmaz — çizim yolunda çağrılabilir.
/// 2. **Tazeleme seyrektir ve arka plandadır.** `refreshIfNeeded` en fazla
///    `minimumInterval` (varsayılan 5 sn) sıklığında çalışır, yani 1 Hz'lik saatin
///    beşte biri; süreç `ExternalCommand` ile arka plan kuyruğunda koşar ve ana aktör
///    yalnız askıya alınır. Kullanıcı `cd` yaptığında aralık beklenmez, çünkü ekranda
///    yanlış deponun bilgisi kalırdı.
@MainActor
@Observable
final class GitStatusMonitor {

    /// 1 Hz'lik durum çubuğu saatinden bilinçli olarak AYRI ve çok daha seyrek.
    ///
    /// `nonisolated`: bu sabit AŞAĞIDAKİ init'in varsayılan argümanıdır ve varsayılan
    /// argüman ifadeleri yalıtımsız bağlamda değerlendirilir. Projede
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` olduğu için işaretlenmezse MainActor'a
    /// bağlanır ve Swift 6 dilinde HATA olur.
    nonisolated static let defaultMinimumInterval: TimeInterval = 5

    /// Önbelleğin ait olduğu dizin. Başka bir dizin sorulduğunda önbellek verilmez.
    private(set) var directory: String?
    private(set) var detail: GitStatusDetail?

    private let runner: any GitCommandRunning
    private let minimumInterval: TimeInterval
    private var lastAttemptAt: Date?
    private var isRefreshing = false

    /// `runner` varsayılanı init'in İÇİNDE kurulur: varsayılan argüman ifadeleri
    /// yalıtımsız bağlamda değerlendirilir, `GitProcessRunner` ise `MainActor`'a bağlıdır.
    init(runner: (any GitCommandRunning)? = nil,
         minimumInterval: TimeInterval = defaultMinimumInterval) {
        self.runner = runner ?? GitProcessRunner()
        self.minimumInterval = minimumInterval
    }

    /// Önbellekteki durum. SÜREÇ BAŞLATMAZ — çizim yolundan çağrılabilir.
    func status(forDirectory directory: String?) -> GitStatusDetail? {
        guard let directory, directory == self.directory else { return nil }
        return detail
    }

    /// Gerekiyorsa tazeler: dizin değiştiyse hemen, aksi hâlde en erken
    /// `minimumInterval` sonra. Aynı anda birden çok tazeleme çalışmaz.
    func refreshIfNeeded(directory newDirectory: String?, now: Date = Date()) async {
        guard let newDirectory else {
            // Panel yok ya da dizin bilinmiyor: eski deponun bilgisi ekranda kalmamalı.
            directory = nil
            detail = nil
            lastAttemptAt = nil
            return
        }

        if newDirectory != directory {
            // Yeni dizinin sonucu gelene kadar ESKİ sayılar gösterilmez.
            directory = newDirectory
            detail = nil
            lastAttemptAt = nil
        } else if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < minimumInterval {
            return
        }

        guard !isRefreshing else { return }
        isRefreshing = true
        lastAttemptAt = now
        defer { isRefreshing = false }

        guard let statusOutput = await runner.run(GitStatusReader.statusArguments, in: newDirectory) else {
            // Depo değil (ya da git yok): dal bile gösterilmez.
            if directory == newDirectory { detail = nil }
            return
        }
        let logOutput = await runner.run(GitStatusReader.lastCommitArguments, in: newDirectory) ?? ""

        // Bu arada kullanıcı `cd` yapmış olabilir; eski dizinin sonucu yazılmaz.
        guard directory == newDirectory else { return }
        detail = GitStatusReader.detail(statusOutput: statusOutput, logOutput: logOutput)
    }
}
