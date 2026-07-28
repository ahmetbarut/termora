import Foundation

/// Kayıtlı bir SSH profilinin kimlik doğrulama yöntemi (briefs/2 alan listesi).
///
/// Termora HİÇBİR yöntemde parola sormaz ve saklamaz: parola gerekiyorsa `ssh` kendi
/// akışında terminalde sorar (briefs/2 "Parola gerekiyorsa güvenli macOS giriş
/// yöntemlerini kullanmalı"). Yöntem yalnız üretilen komut satırını etkiler.
enum SSHAuthenticationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Hiçbir şey dayatılmaz: ssh agent'ı, config'i ve varsayılan anahtarları kendisi çözer.
    case automatic
    /// Yalnız bu yöntemde `-i <yol>` gönderilir.
    case privateKey
    /// Parolayı ssh'ın kendisi terminalde sorar; Termora ne sorar ne saklar.
    case password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .privateKey: return "Private Key"
        case .password: return "Password"
        }
    }

    /// Ayarlar ekranında yöntemin ne YAPTIĞINI anlatan tek cümle.
    var explanation: String {
        switch self {
        case .automatic:
            return "Lets ssh pick the identity from your agent and ~/.ssh/config."
        case .privateKey:
            return "Sends the key file path to ssh. Termora never reads or stores the key itself."
        case .password:
            return "ssh asks for the password in the terminal. Termora never stores it."
        }
    }
}

/// Kayıtlı SSH profili (briefs/2 "SSH Yöneticisi" alan listesi).
///
/// GÜVENLİK: private key'in İÇERİĞİ hiçbir zaman burada durmaz — yalnız `identityFile`
/// YOLU saklanır ve `-i` ile ssh'a verilir. Parola da saklanmaz (bkz.
/// `SSHAuthenticationMethod`).
struct SSHHost: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Görünen ad.
    var name: String
    /// Host (ad ya da IP).
    var hostName: String
    /// nil → ssh'ın varsayılanı (22) ya da config'teki değer.
    var port: Int?
    var user: String?
    var authenticationMethod: SSHAuthenticationMethod = .automatic
    /// Private key YOLU; içeriği asla kopyalanmaz.
    var identityFile: String?
    /// Uzak makinede geçilecek dizin.
    var startupDirectory: String?
    /// Uzak makinede çalıştırılacak komut.
    var startupCommand: String?
    var tags: [String] = []
    /// "#RRGGBB"; listede renk noktası olarak gösterilir (renk TEK sinyal değildir).
    var colorHex: String?
    var proxyJump: String?
    /// Son bağlantının BAŞLATILDIĞI an. ssh süreci terminal panelinin içinde çalıştığı
    /// için oturumun ne zaman bittiği buradan bilinemez; bkz. `SSHHostRowModel`.
    var lastConnectedAt: Date?

    init(id: UUID = UUID(),
         name: String,
         hostName: String,
         port: Int? = nil,
         user: String? = nil,
         authenticationMethod: SSHAuthenticationMethod = .automatic,
         identityFile: String? = nil,
         startupDirectory: String? = nil,
         startupCommand: String? = nil,
         tags: [String] = [],
         colorHex: String? = nil,
         proxyJump: String? = nil,
         lastConnectedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.hostName = hostName
        self.port = port
        self.user = user
        self.authenticationMethod = authenticationMethod
        self.identityFile = identityFile
        self.startupDirectory = startupDirectory
        self.startupCommand = startupCommand
        self.tags = tags
        self.colorHex = colorHex
        self.proxyJump = proxyJump
        self.lastConnectedAt = lastConnectedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hostName, port, user, authenticationMethod, identityFile
        case startupDirectory, startupCommand, tags, colorHex, proxyJump, lastConnectedAt
    }
}

// MARK: - İleri uyumlu çözme

extension SSHHost {
    /// Elle yazılmış çözücü (bkz. `TerminalProfile` / `Workspace` ile aynı kural):
    /// sentezlenmiş `init(from:)` özellik varsayılanlarını YOK SAYAR ve eksik anahtarda
    /// fırlatır. Öyle kalsaydı modele eklenen tek bir yeni alan, kullanıcının diskteki
    /// TÜM SSH profillerini `SSHHostStore` gözünde bozuk yapardı.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Kimlik, ad ve host UYDURULMAZ: taze bir UUID kaydın kimliğini koparır, uydurma
        // bir host kullanıcıyı YANLIŞ makineye bağlardı. Eksikse yalnız bu kayıt atlanır.
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hostName = try container.decode(String.self, forKey: .hostName)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        // Yöntem ham değerden okunur: ileride eklenen bir yöntem, doğrudan enum'a
        // çözdürülseydi eski sürümde TÜM kaydı düşürürdü.
        authenticationMethod = try container.decodeIfPresent(String.self, forKey: .authenticationMethod)
            .flatMap(SSHAuthenticationMethod.init(rawValue:)) ?? .automatic
        identityFile = try container.decodeIfPresent(String.self, forKey: .identityFile)
        startupDirectory = try container.decodeIfPresent(String.self, forKey: .startupDirectory)
        startupCommand = try container.decodeIfPresent(String.self, forKey: .startupCommand)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        proxyJump = try container.decodeIfPresent(String.self, forKey: .proxyJump)
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
    }
}

// MARK: - Bağlanılabilir hedef

/// Bağlanılabilir tek bir hedef: ya kayıtlı bir profil ya da `~/.ssh/config` takma adı.
/// Liste, komut paleti ve komut üretimi aynı tipi kullanır.
enum SSHTarget: Identifiable, Equatable {
    case profile(SSHHost)
    case configHost(SSHConfigHost)

    var id: String {
        switch self {
        case let .profile(host): return "ssh.profile.\(host.id.uuidString)"
        case let .configHost(host): return "ssh.config.\(host.alias)"
        }
    }

    var displayName: String {
        switch self {
        case let .profile(host):
            let trimmed = host.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? host.hostName : trimmed
        case let .configHost(host):
            return host.alias
        }
    }

    /// "deploy@pinro.app:2222" — bilinen alanlardan kurulan hedef metni.
    var destinationText: String {
        switch self {
        case let .profile(host):
            return Self.destinationText(user: host.user, hostName: host.hostName, port: host.port)
        case let .configHost(host):
            return Self.destinationText(user: host.user,
                                        hostName: host.hostName ?? host.alias,
                                        port: host.port)
        }
    }

    var userText: String? {
        switch self {
        case let .profile(host): return SSHCommand.nonBlank(host.user)
        case let .configHost(host): return SSHCommand.nonBlank(host.user)
        }
    }

    var tags: [String] {
        switch self {
        case let .profile(host): return host.tags
        case .configHost: return []
        }
    }

    var lastConnectedAt: Date? {
        switch self {
        case let .profile(host): return host.lastConnectedAt
        case .configHost: return nil
        }
    }

    var arguments: [String] { SSHCommand.arguments(for: self) }

    /// Sekmede çalıştırılacak, her alanı alıntılanmış komut satırı.
    var commandLine: String { SSHCommand.commandLine(arguments) }

    private static func destinationText(user: String?, hostName: String, port: Int?) -> String {
        var text = hostName
        if let user = SSHCommand.nonBlank(user) {
            text = "\(user)@\(text)"
        }
        if let port, SSHCommand.isUsablePort(port) {
            text += ":\(port)"
        }
        return text
    }
}

// MARK: - Komut üretimi

/// `/usr/bin/ssh` çağrısını ARGÜMAN DİZİSİ olarak kuran saf çekirdek (briefs/2: ilk
/// aşamada yeni bir SSH protokolü uygulanmaz, sistemdeki ssh kullanılır).
///
/// İki kural bu tipin tamamını açıklar:
///
/// 1. **known_hosts gevşetilmez.** Üretilen komut hiçbir `-o` seçeneği taşımaz; yani
///    `StrictHostKeyChecking`, `UserKnownHostsFile` gibi doğrulama ayarlarına
///    DOKUNULMAZ (briefs/2). Kullanıcının kendi config'i neyse o geçerlidir.
/// 2. **Kabuk enjeksiyonu argüman düzeyinde kesilir.** Alanlar kullanıcıdan gelir;
///    komut string birleştirmesiyle kurulmaz. Önce argüman dizisi üretilir, kabuğa
///    verilecek metin ise her öğe ayrı ayrı alıntılanarak (`posixQuoted`) elde edilir.
///    Ayrıca hedefin önüne `--` konur: `-oProxyCommand=…` gibi bir "host adı" bile
///    ssh tarafından seçenek olarak okunamaz.
enum SSHCommand {

    static let executablePath = "/usr/bin/ssh"

    /// Bir hedefin tam argüman dizisi; ilk öğe çalıştırılacak program yoludur.
    static func arguments(for target: SSHTarget) -> [String] {
        switch target {
        case let .profile(host): return arguments(for: host)
        case let .configHost(host): return arguments(forConfigAlias: host.alias)
        }
    }

    static func arguments(for host: SSHHost) -> [String] {
        var arguments = [executablePath]

        if let port = host.port, isUsablePort(port) {
            arguments += ["-p", String(port)]
        }
        // Anahtar YOLU gönderilir, içeriği değil (briefs/2).
        if host.authenticationMethod == .privateKey, let identityFile = nonBlank(host.identityFile) {
            arguments += ["-i", identityFile]
        }
        if let proxyJump = nonBlank(host.proxyJump) {
            arguments += ["-J", proxyJump]
        }

        let remoteCommand = self.remoteCommand(directory: host.startupDirectory,
                                               command: host.startupCommand)
        if remoteCommand != nil {
            // Uzak komut verildiğinde ssh TTY ayırmaz; `-t` olmadan ekran düzenleyiciler
            // ve devamındaki etkileşimli kabuk çalışmazdı.
            arguments.append("-t")
        }

        arguments += ["--", destination(for: host)]
        if let remoteCommand {
            arguments.append(remoteCommand)
        }
        return arguments
    }

    /// `~/.ssh/config` takma adı TEK BAŞINA gönderilir: HostName/User/Port değerlerini
    /// biz tekrar göndermeyiz, çünkü ssh aynı config'i kendisi okur ve bizim ayrıştırma
    /// kopyamız ondan sapabilir (`Match` blokları, `Include`, joker desenler…).
    static func arguments(forConfigAlias alias: String) -> [String] {
        [executablePath, "--", alias]
    }

    /// Argüman dizisinden kabuğa verilebilir tek satır. Her öğe ayrı ayrı alıntılanır.
    static func commandLine(_ arguments: [String]) -> String {
        arguments.map(posixQuoted).joined(separator: " ")
    }

    /// POSIX kabuk alıntılaması: güvenli karakterlerden oluşan değer olduğu gibi kalır,
    /// gerisi tek tırnağa alınır ve içindeki tek tırnak `'\''` ile kapatılır.
    static func posixQuoted(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")
        if value.unicodeScalars.allSatisfy({ safe.contains(Character($0)) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isUsablePort(_ port: Int) -> Bool {
        (1...65_535).contains(port)
    }

    static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func destination(for host: SSHHost) -> String {
        let hostName = host.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let user = nonBlank(host.user) else { return hostName }
        return "\(user)@\(hostName)"
    }

    /// Başlangıç dizini ve komutu TEK bir uzak argümana çevrilir.
    ///
    /// Sonuna `exec "${SHELL:-/bin/sh}" -l` eklenir: uzak komut verilen bir ssh oturumu
    /// komut biter bitmez kapanırdı; kullanıcı bağlantıyı etkileşimli kullanmak istiyor.
    /// Komut `;` ile ayrılır ki başarısız bir başlangıç komutu bile kullanılabilir bir
    /// kabuk bıraksın; `cd` ile komut arasında `&&` vardır ki yanlış dizinde çalışmasın.
    private static func remoteCommand(directory: String?, command: String?) -> String? {
        var parts: [String] = []
        if let directory = nonBlank(directory) {
            parts.append("cd -- \(posixQuoted(directory))")
        }
        if let command = nonBlank(command) {
            parts.append(command)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " && ") + "; exec \"${SHELL:-/bin/sh}\" -l"
    }
}

// MARK: - Sekmede başlatma

/// Bir SSH hedefini YENİ BİR SEKMEDE açmak için gereken profil.
///
/// Kabuk kullanıcının varsayılanı kalır ve ssh onun İÇİNDE çalışır (`exec` ile kabuk
/// değiştirilmez): bağlantı düştüğünde sekme kapanmaz, kullanıcı aynı satırla yeniden
/// bağlanabilir (briefs/2 "Bağlantı kesildiğinde tekrar bağlanma seçeneği sunmalıdır").
enum SSHLaunch {

    /// `WorkspaceViewModel.newTab(profile:)`e verilecek geçici profil.
    ///
    /// Kimliği her seferinde tazedir ve `ProfileStore`'da karşılığı YOKTUR: bu bir
    /// kullanıcı profili değil, tek seferlik bir başlatma tarifidir.
    static func profile(for target: SSHTarget) -> TerminalProfile {
        TerminalProfile(name: target.displayName, startupCommand: target.commandLine)
    }
}
