import Darwin
import Foundation

/// `~/.ssh/config` içindeki bağlanılabilir tek bir hedef.
///
/// Buradaki değerler YALNIZ GÖSTERİM içindir. Bağlanırken takma ad tek başına
/// `/usr/bin/ssh`'a verilir (bkz. `SSHCommand.arguments(forConfigAlias:)`), çünkü asıl
/// çözümlemeyi ssh'ın kendisi yapar.
struct SSHConfigHost: Equatable, Identifiable, Sendable {
    /// `Host` satırındaki joker İÇERMEYEN desen: `ssh <alias>` ile bağlanılabilir.
    let alias: String
    var hostName: String?
    var user: String?
    var port: Int?
    var identityFile: String?
    var proxyJump: String?

    var id: String { alias }

    init(alias: String,
         hostName: String? = nil,
         user: String? = nil,
         port: Int? = nil,
         identityFile: String? = nil,
         proxyJump: String? = nil) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
    }
}

/// Ayrıştırılan config'in KAYNAK SIRASINDAKİ öğeleri. `Include` bir öğedir: içerilen
/// dosyanın hostları tam olarak bu noktaya girer.
enum SSHConfigEntry: Equatable, Sendable {
    case host(SSHConfigHost)
    case include(String)
}

struct SSHConfigParseResult: Equatable, Sendable {
    let entries: [SSHConfigEntry]

    var hosts: [SSHConfigHost] {
        entries.compactMap { entry in
            if case let .host(host) = entry { return host }
            return nil
        }
    }

    var includePatterns: [String] {
        entries.compactMap { entry in
            if case let .include(pattern) = entry { return pattern }
            return nil
        }
    }
}

/// `~/.ssh/config` ayrıştırıcısı (briefs/2: "Mevcut SSH config hostlarını listeleyebilmeli").
///
/// Kapsam kararları — hepsi BİLEREK verildi:
///
/// - **Joker desenler listelenmez.** `Host *`, `Host web?`, `Host !prod` bağlanılabilir bir
///   hedef değildir; listede görünmezler. Ayarları somut hostlara da YAZILMAZ: bağlanırken
///   ssh aynı dosyayı kendisi okuyup uygular, bizim çıkarımımız yalnız gösterimdir.
/// - **`Include` İZLENİR.** Config'ini `~/.ssh/config.d/*` gibi parçalara bölen kullanıcı
///   listesini boş görmemeli. İçerilen dosyalar öğe sırasında, tam yerinde açılır; aynı
///   dosya iki kez okunmaz ve özyineleme derinliği sınırlıdır (kendini içeren bir config
///   uygulamayı dondurmaz).
/// - **`Match` blokları atlanır.** İçindeki ayarlar bir önceki `Host` bloğuna yazılsaydı
///   listede yanlış kullanıcı/port gösterilirdi.
/// - **Yorum yalnız satır başındadır** (`ssh_config(5)`: "lines starting with '#'").
///   Satır sonuna yazılan `# not` metni değerin parçasıdır — ssh de böyle davranır.
/// - **Dosya yoksa boş liste** döner; hiçbir yol çökmez.
enum SSHConfigParser {

    /// Tek bir dosyanın içeriğini kaynak sırasında öğelere çevirir. Saf: dosya sistemine
    /// dokunmaz, `Include` yalnız kaydedilir.
    static func parse(_ contents: String) -> SSHConfigParseResult {
        var entries: [SSHConfigEntry] = []
        /// Açık `Host` bloğunun ürettiği öğelerin indeksleri; sonraki anahtarlar bunlara yazılır.
        var openHostIndices: [Int] = []

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let (key, value) = keyAndValue(in: String(rawLine)) else { continue }

            switch key.lowercased() {
            case "host":
                openHostIndices = []
                for pattern in tokens(in: value) where !isWildcard(pattern) {
                    entries.append(.host(SSHConfigHost(alias: pattern)))
                    openHostIndices.append(entries.count - 1)
                }
            case "match":
                // `Match` bloğu bir hedef üretmez ve ayarları bir önceki hosta sızmaz.
                openHostIndices = []
            case "include":
                for pattern in tokens(in: value) {
                    entries.append(.include(pattern))
                }
            default:
                guard !openHostIndices.isEmpty else { continue }
                for index in openHostIndices {
                    guard case let .host(existing) = entries[index] else { continue }
                    var host = existing
                    apply(key: key.lowercased(), value: value, to: &host)
                    entries[index] = .host(host)
                }
            }
        }

        return SSHConfigParseResult(entries: entries)
    }

    /// Kök config'i ve içerdiği dosyaları tek bir listeye çözer.
    ///
    /// - Parameters:
    ///   - configContents: kök dosyanın içeriği; `nil` (dosya yok) → boş liste.
    ///   - includeReader: bir `Include` desenini, içerilen dosyaların İÇERİKLERİNE çevirir.
    ///     Dosya sistemine dokunan tek nokta budur; testte sözlükle beslenir.
    ///   - includeDepthLimit: özyineleme sınırı; kendini içeren config dondurmasın diye.
    static func hosts(configContents: String?,
                      includeReader: (String) -> [String],
                      includeDepthLimit: Int = 8) -> [SSHConfigHost] {
        guard let configContents else { return [] }

        var collected: [SSHConfigHost] = []
        var seenAliases = Set<String>()

        func walk(_ contents: String, depth: Int) {
            for entry in parse(contents).entries {
                switch entry {
                case let .host(host):
                    // ssh'ta İLK değer kazanır: aynı takma ad tekrar geçerse ilki kalır.
                    if seenAliases.insert(host.alias).inserted {
                        collected.append(host)
                    }
                case let .include(pattern):
                    guard depth < includeDepthLimit else { continue }
                    for included in includeReader(pattern) {
                        walk(included, depth: depth + 1)
                    }
                }
            }
        }

        walk(configContents, depth: 0)
        return collected
    }

    /// Kullanıcının gerçek config'ini okuyan kolaylık sarmalayıcı.
    /// Dosya yoksa ya da okunamıyorsa boş liste döner.
    static func loadUserConfig(sshDirectory: String = NSHomeDirectory() + "/.ssh") -> [SSHConfigHost] {
        let configPath = sshDirectory + "/config"
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else { return [] }

        // Aynı dosyayı iki kez okumamak hem döngüyü hem de yinelenen hostları keser.
        var visited: Set<String> = [configPath]
        return hosts(configContents: contents) { pattern in
            expandIncludePaths(pattern, relativeTo: sshDirectory).compactMap { path in
                guard visited.insert(path).inserted else { return nil }
                return try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
    }

    // MARK: - Satır ayrıştırma

    /// `Key value`, `Key=value` ve `Key = value` biçimlerini tek kurala indirir.
    /// Yorum ve boş satırlarda `nil` döner.
    private static func keyAndValue(in line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        guard let separatorIndex = trimmed.firstIndex(where: { $0 == "=" || $0.isWhitespace }) else {
            return nil // Değeri olmayan anahtar bir hedef tanımlamaz.
        }
        let key = String(trimmed[trimmed.startIndex..<separatorIndex])
        var rest = trimmed[separatorIndex...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("=") {
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !key.isEmpty, !rest.isEmpty else { return nil }
        return (key, rest)
    }

    /// Değeri boşluklardan ayırır; tırnak içindeki boşluk korunur.
    private static func tokens(in value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false
        for character in value {
            if character == "\"" {
                isQuoted.toggle()
                continue
            }
            if character.isWhitespace, !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func isWildcard(_ pattern: String) -> Bool {
        pattern.contains("*") || pattern.contains("?") || pattern.hasPrefix("!")
    }

    private static func apply(key: String, value: String, to host: inout SSHConfigHost) {
        let unquoted = tokens(in: value).first ?? value
        switch key {
        case "hostname":
            if host.hostName == nil { host.hostName = unquoted }
        case "user":
            if host.user == nil { host.user = unquoted }
        case "port":
            // Sayı olmayan port UYDURULMAZ; alan boş kalır.
            if host.port == nil { host.port = Int(unquoted) }
        case "identityfile":
            if host.identityFile == nil { host.identityFile = unquoted }
        case "proxyjump":
            if host.proxyJump == nil { host.proxyJump = unquoted }
        default:
            break
        }
    }

    // MARK: - Include yolları

    /// Bir `Include` desenini gerçek dosya yollarına çevirir.
    /// `~` genişletilir, göreli desenler `~/.ssh` altında aranır, joker `glob(3)` ile açılır.
    private static func expandIncludePaths(_ pattern: String, relativeTo directory: String) -> [String] {
        let expanded = (pattern as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : directory + "/" + expanded

        var results = glob_t()
        defer { globfree(&results) }
        guard glob(absolute, 0, nil, &results) == 0 else { return [] }

        var paths: [String] = []
        for index in 0..<Int(results.gl_pathc) {
            guard let cString = results.gl_pathv[index] else { continue }
            paths.append(String(cString: cString))
        }
        return paths
    }
}
