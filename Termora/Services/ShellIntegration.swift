import Foundation

// MARK: - Shell ailesi

/// Kancaları kurabildiğimiz kabuklar (briefs/1 "Shell integration").
///
/// Desteklenmeyen bir kabuk SESSİZCE zsh sayılmaz: yanlış sözdizimini kullanıcının rc
/// dosyasına yazmak onun kabuğunu açılmaz hâle getirebilirdi.
enum ShellFamily: String, CaseIterable, Sendable {
    case zsh
    case bash

    init?(shellPath: String) {
        switch (shellPath as NSString).lastPathComponent {
        case "zsh": self = .zsh
        case "bash": self = .bash
        default: return nil
        }
    }

    /// Kancaların yazılacağı dosya.
    ///
    /// bash için `.bashrc` DEĞİL `.bash_profile`: macOS'ta Terminal her kabuğu login
    /// kabuk olarak açar ve login kabuk `.bashrc`'yi okumaz.
    var startupFileName: String {
        switch self {
        case .zsh: ".zshrc"
        case .bash: ".bash_profile"
        }
    }

    var displayName: String {
        switch self {
        case .zsh: "zsh"
        case .bash: "bash"
        }
    }
}

// MARK: - Kancalar

/// Kullanıcının başlangıç dosyasına yazılan OSC 133 kancaları ve o dosya üzerindeki SAF
/// metin dönüşümleri.
///
/// # Neden saf
///
/// Bu, Termora'nın kullanıcının KENDİ dosyasına yazan tek özelliği. Dönüşümü saf tutmak,
/// "kur → kaldır dosyayı orijinaline döndürür" gibi bir iddiayı diske hiç dokunmadan
/// sınanabilir kılıyor.
enum ShellIntegration {

    /// Blok sınırları. Kaldırma TAM OLARAK bu iki satır arasını siler; kullanıcının kendi
    /// satırlarına dokunmaz.
    static let beginMarker = "# >>> termora shell integration >>>"
    static let endMarker = "# <<< termora shell integration <<<"

    /// İki kez kaynak alınmaya karşı koruma. Kullanıcı rc dosyasını elle yeniden
    /// yükleyebilir; korumasız her prompt iki kat işaret yayardı.
    static let guardVariable = "__TERMORA_SHELL_INTEGRATION"

    /// Kabuğa göre kanca metni.
    ///
    /// İki ortak kural:
    /// - `case $- in *i*)` — ETKİLEŞİMSİZ kabukta hiçbir şey yapılmaz. Bir betiğin
    ///   çıktısına kaçış dizisi karıştırmak, o çıktıyı ayrıştıran her aracı bozardı.
    /// - Koruma değişkeni ikinci kurulumu engeller.
    static func snippet(for family: ShellFamily) -> String {
        switch family {
        case .zsh: zshSnippet
        case .bash: bashSnippet
        }
    }

    private static let zshSnippet = """
        # Termora marks where each command starts and ends (OSC 133) so the app knows
        # a command's exit code instead of guessing it. Remove this block any time.
        case $- in
          *i*)
            if [ -z "${\(guardVariable)-}" ]; then
              \(guardVariable)=1
              __termora_precmd() { printf '\\033]133;D;%s\\007\\033]133;A\\007' "$?" }
              __termora_preexec() { printf '\\033]133;C\\007' }
              autoload -Uz add-zsh-hook 2>/dev/null && {
                add-zsh-hook precmd __termora_precmd
                add-zsh-hook preexec __termora_preexec
              }
              PS1="%{$(printf '\\033]133;B\\007')%}$PS1"
            fi
            ;;
        esac
        """

    private static let bashSnippet = """
        # Termora marks where each command starts and ends (OSC 133) so the app knows
        # a command's exit code instead of guessing it. Remove this block any time.
        case $- in
          *i*)
            if [ -z "${\(guardVariable)-}" ]; then
              \(guardVariable)=1
              __termora_prompt() {
                local __termora_status=$?
                printf '\\033]133;D;%s\\007\\033]133;A\\007' "$__termora_status"
              }
              PROMPT_COMMAND="__termora_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
              PS1="\\[$(printf '\\033]133;B\\007')\\]$PS1"
              trap 'printf "\\033]133;C\\007"' DEBUG
            fi
            ;;
        esac
        """

    static func isInstalled(in contents: String) -> Bool {
        contents.contains(beginMarker)
    }

    /// Bloğu ekler. Zaten kuruluysa ÖNCE kaldırılır: iki kez kurmak dosyaya iki blok
    /// bırakmaz ve içerik güncellenmiş olur.
    ///
    /// Dosyanın sonunda satır sonu yoksa eklenir; yoksa Termora'nın ilk satırı
    /// kullanıcının son satırına yapışır ve ikisi de bozulur.
    static func installing(into contents: String, family: ShellFamily) -> String {
        var base = uninstalling(from: contents)
        if !base.isEmpty, !base.hasSuffix("\n") { base += "\n" }
        return base + beginMarker + "\n" + snippet(for: family) + "\n" + endMarker + "\n"
    }

    /// Bloğu çıkarır ve kullanıcının satırlarını olduğu gibi bırakır.
    /// Blok yoksa metin AYNEN döner.
    static func uninstalling(from contents: String) -> String {
        guard let begin = contents.range(of: beginMarker) else { return contents }
        // Bitiş işareti yoksa (dosya elle kırpılmış) bloğun başından SONUNA kadar silinir;
        // yarım bir blok bırakmak kabuğu bozardı.
        let tail = contents[begin.upperBound...]
        guard let end = tail.range(of: endMarker) else {
            return String(contents[..<begin.lowerBound])
        }
        var after = String(tail[end.upperBound...])
        if after.hasPrefix("\n") { after.removeFirst() }
        return String(contents[..<begin.lowerBound]) + after
    }
}

// MARK: - Diske yazan kurulumcu

/// Dosya erişimi dikişi; testler kullanıcının gerçek rc dosyasına DOKUNMAZ.
@MainActor
protocol ShellIntegrationFileStoring: AnyObject {
    /// Dosya yoksa nil (hata değil): henüz `.zshrc`'si olmayan kullanıcı normaldir.
    func read(_ path: String) throws -> String?
    func write(_ text: String, to path: String) throws
}

@MainActor
final class ShellIntegrationDiskFiles: ShellIntegrationFileStoring {
    func read(_ path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    func write(_ text: String, to path: String) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Kancaları kullanıcının başlangıç dosyasına kuran/kaldıran tek yer.
///
/// Bu sınıf KENDİLİĞİNDEN çalışmaz: yalnız kullanıcı düğmeye bastığında çağrılır.
/// Termora hiçbir koşulda sessizce dotfile'a yazmaz.
@MainActor
final class ShellIntegrationInstaller {

    /// İlk kurulumdan önce alınan yedeğin uzantısı.
    static let backupSuffix = ".termora-backup"

    private let home: String
    private let files: any ShellIntegrationFileStoring

    /// `files` varsayılanı init'in İÇİNDE kurulur: varsayılan argüman ifadeleri yalıtımsız
    /// bağlamda değerlendirilir, `ShellIntegrationDiskFiles` ise MainActor'a bağlıdır.
    init(home: String = NSHomeDirectory(), files: (any ShellIntegrationFileStoring)? = nil) {
        self.home = home
        self.files = files ?? ShellIntegrationDiskFiles()
    }

    func startupFilePath(for family: ShellFamily) -> String {
        (home as NSString).appendingPathComponent(family.startupFileName)
    }

    func isInstalled(for family: ShellFamily) -> Bool {
        let contents = (try? files.read(startupFilePath(for: family))) ?? nil
        return ShellIntegration.isInstalled(in: contents ?? "")
    }

    /// Bloğu kurar. Yedek ÖNCE yazılır: kullanıcının dosyası bir hata hâlinde kaybolmaz.
    func install(for family: ShellFamily) throws {
        let path = startupFilePath(for: family)
        let current = try files.read(path)
        try backUpIfNeeded(current, at: path)
        try files.write(ShellIntegration.installing(into: current ?? "", family: family), to: path)
    }

    func uninstall(for family: ShellFamily) throws {
        let path = startupFilePath(for: family)
        guard let current = try files.read(path) else { return }
        try files.write(ShellIntegration.uninstalling(from: current), to: path)
    }

    /// Yedek yalnız BİR KEZ alınır ve yalnız gerçek bir içerik varsa.
    ///
    /// İkinci kurulumda yedeği ezmek, ilk yedeği (kullanıcının Termora'ya hiç dokunmamış
    /// dosyasını) kaybetmek olurdu. Dosya hiç yoksa yedeklenecek bir şey de yoktur.
    private func backUpIfNeeded(_ current: String?, at path: String) throws {
        guard let current, !current.isEmpty else { return }
        let backupPath = path + Self.backupSuffix
        guard (try files.read(backupPath)) == nil else { return }
        try files.write(current, to: backupPath)
    }
}

// MARK: - Metinler

/// Ayarlar ve onboarding'de görünen TÜM shell integration metni.
///
/// `body` dışında tutuluyor (proje kalıbı): kullanıcının kendi dosyasına yazan bir
/// özelliğin ne yaptığını söyleyen cümleler testle sabitlenmeli.
enum ShellIntegrationContent {

    static let title = "Shell Integration"

    static let installTitle = "Install Shell Integration"
    static let uninstallTitle = "Remove Shell Integration"

    /// Kullanıcı hangi dosyaya yazılacağını ÖNCEDEN bilmeli; onay ancak bilgiyle olur.
    static func explanation(for family: ShellFamily) -> String {
        "Termora adds a marked block to ~/\(family.startupFileName) so it knows when a "
            + "command starts and ends, and its exit code, instead of guessing. "
            + "You can remove it again from here at any time."
    }

    /// Kurulum yalnız YENİ kabuklarda etkindir; kullanıcı hiçbir şey olmadığını sanıp
    /// tekrar tekrar basmasın.
    static let installedNote = "Installed. It starts working in new tabs and windows."

    /// Desteklenmeyen kabukta ölü bir düğme yerine dürüst bir cümle.
    static func unsupportedShellNote(shellPath: String) -> String {
        let name = (shellPath as NSString).lastPathComponent
        let shown = name.isEmpty ? shellPath : name
        return "Termora can only install shell integration for zsh and bash, and this "
            + "pane runs \(shown)."
    }
}

// MARK: - OSC 133 işaretleri

/// Kabuğun yaydığı komut sınırı işareti.
///
/// Termora bunlarla komutun ne zaman başladığını, ne zaman bittiğini ve ÇIKIŞ KODUNU
/// bilir — libproc yoklamasıyla tahmin etmek yerine.
enum ShellIntegrationMarker: Equatable {
    case promptStart
    case commandStart
    case outputStart
    /// Çıkış kodu bilinmiyorsa nil. 0 VARSAYILMAZ: başarısız bir komutu başarılı
    /// göstermek, kullanıcının gördüğü her şeyi yalanlardı.
    case commandEnd(exitCode: Int?)

    /// `133;D;1;aid=42` gibi bir OSC yükünü ayrıştırır. İlgisiz ya da bozuk yük nil verir.
    init?(payload: String) {
        let parts = payload.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "133" else { return nil }
        switch parts[1] {
        case "A": self = .promptStart
        case "B": self = .commandStart
        case "C": self = .outputStart
        case "D":
            // Ek parametreler (`aid=`) yok sayılır; kod yalnız üçüncü alandan okunur.
            let code = parts.count >= 3 ? Int(parts[2]) : nil
            self = .commandEnd(exitCode: code)
        default: return nil
        }
    }
}
