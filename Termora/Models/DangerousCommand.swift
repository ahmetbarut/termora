import Foundation

/// briefs/2 "Tehlikeli Komut Koruması": geri dönüşü zor işlemlerde ek uyarı.
///
/// # Bu koruma NEREYE bakar
///
/// Brief'in sınırı çok net: *"Koruma sistemi shell davranışını bozmamalı ve her komuta
/// müdahale etmemelidir. Yalnızca yüksek güvenle tespit edilen işlemlerde uyarı
/// verilmelidir."* Bu yüzden Termora kullanıcının terminale yazdığı her satırı SÜZMEZ —
/// öyle bir şey hem shell davranışını bozar hem de güvenilir yapılamaz.
///
/// Dürüst yüzey, Termora'nın KULLANICI ADINA çalıştırdığı komutlardır: workspace başlangıç
/// komutları, profil başlangıç komutu ve SSH uzak başlangıç komutu. Bunlar kullanıcı
/// onaylamadan önce burada incelenir.
///
/// # Seviye çizgisi nerede
///
/// - `.high` — geri dönüşü olmayan ve kapsamı projeyi AŞAN işlem: kök/ev/sistem klasörünü
///   silmek, diski biçimlendirmek, aygıta doğrudan yazmak, veritabanını düşürmek, korunan
///   dizinlerin izinlerini değiştirmek, uzak sunucuda toplu silmek.
/// - `.caution` — yıkıcı ama kapsamı bulunduğun yerle sınırlı: çalışma klasörünü silmek,
///   `git reset --hard`, tek bir docker volume'ünü silmek.
/// - Uyarı YOK — `rm -rf build` gibi günlük iş. `rm -rf /` ile `rm -rf build` aynı şey
///   değildir; ikincisine uyarı çıkarmak korumanın kendisini gürültüye çevirir.
enum DangerousCommand {

    /// Komutu inceler; yüksek güvenle tespit edilen bir işlem yoksa `nil` döner.
    /// Zincirlenmiş komutlarda EN AĞIR bulgu kazanır.
    static func inspect(_ command: String) -> DangerousCommandWarning? {
        warnings(in: command, isRemote: false).max { $0.risk < $1.risk }
    }

    private static func warnings(in command: String, isRemote: Bool) -> [DangerousCommandWarning] {
        segments(of: command).compactMap { warning(for: $0, isRemote: isRemote) }
    }

    // MARK: - Tek bir alt komut

    private static func warning(for segment: String, isRemote: Bool) -> DangerousCommandWarning? {
        let tokens = strippingWrappers(tokenize(segment))
        guard let first = tokens.first else { return nil }

        let head = commandName(first)
        let arguments = Array(tokens.dropFirst())
        // İçerik taramaları için: tırnakları çözülmüş, küçük harfe indirilmiş komut.
        let text = tokens.joined(separator: " ").lowercased()

        // SSH kendi başına tehlikeli değildir; TAŞIDIĞI komut tehlikeli olabilir.
        if head == "ssh" { return remoteWarning(arguments: arguments) }

        guard let found = finding(head: head, arguments: arguments, text: text, isRemote: isRemote) else {
            return nil
        }

        return DangerousCommandWarning(
            // Uzakta çalışan hiçbir şey "sadece dikkat" değildir: geri alınamaz ve
            // çoğu zaman üretim sunucusundadır.
            risk: isRemote ? .high : found.risk,
            reason: found.reason,
            command: segment.trimmingCharacters(in: .whitespacesAndNewlines),
            isRemote: isRemote
        )
    }

    private struct Finding {
        let risk: CommandRisk
        let reason: DangerousCommandReason
    }

    private static func finding(head: String,
                                arguments: [String],
                                text: String,
                                isRemote: Bool) -> Finding? {
        if let database = databaseFinding(head: head, arguments: arguments, text: text) { return database }

        switch head {
        case "rm":
            return removeFinding(arguments: arguments, isRemote: isRemote)
        case "dd":
            return arguments.contains { isDeviceOutput($0) }
                ? Finding(risk: .high, reason: .rawDeviceWrite)
                : nil
        case "diskutil":
            return arguments.contains { diskFormattingSubcommands.contains($0.lowercased()) }
                ? Finding(risk: .high, reason: .diskFormat)
                : nil
        case "docker":
            return dockerFinding(arguments: arguments)
        case "git":
            return gitFinding(arguments: arguments)
        case "chmod", "chown":
            return permissionFinding(arguments: arguments)
        default:
            let formatsDisk = head.hasPrefix("mkfs") || head.hasPrefix("newfs")
            return formatsDisk ? Finding(risk: .high, reason: .diskFormat) : nil
        }
    }

    // MARK: - rm

    private static func removeFinding(arguments: [String], isRemote: Bool) -> Finding? {
        // Özyineleme yoksa "geniş kapsamlı" değildir: `rm dosya.log` uyarı almaz.
        guard arguments.contains(where: isRecursiveFlag) else { return nil }

        let targets = arguments.filter { !$0.hasPrefix("-") }
        guard !targets.isEmpty else { return nil }

        let worst = targets.compactMap(deleteFinding(forTarget:)).max { $0.risk < $1.risk }
        if let worst { return isRemote ? Finding(risk: .high, reason: worst.reason) : worst }

        // Uzak sunucuda hedefin dar olması teselli değildir: orada ne olduğunu bilmiyoruz
        // ve geri alma şansı yok (briefs/2 "Uzak sunucuda toplu silme").
        return isRemote ? Finding(risk: .high, reason: .remoteBulkDelete) : nil
    }

    /// Silme hedefinin kapsamı. Mutlak yolun DERİNLİĞİ ölçü olarak kullanılır:
    /// `/usr/local` (2 parça) sistemdir, `/Users/dev/Projects/pinro/build` (5 parça)
    /// bir proje klasörüdür.
    private static func deleteFinding(forTarget rawTarget: String) -> Finding? {
        let target = rawTarget.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !target.isEmpty else { return nil }

        if workingDirectoryTargets.contains(target) {
            return Finding(risk: .caution, reason: .workingDirectoryDelete)
        }

        if homeTargets.contains(target) {
            return Finding(risk: .high, reason: .systemWideDelete)
        }

        for prefix in homePrefixes where target.hasPrefix(prefix) {
            let rest = String(target.dropFirst(prefix.count))
            return pathDepth(rest) <= 1 ? Finding(risk: .high, reason: .systemWideDelete) : nil
        }

        guard target.hasPrefix("/") else { return nil }
        let components = pathComponents(String(target.dropFirst()))
        if components.count <= 2 { return Finding(risk: .high, reason: .systemWideDelete) }
        if let root = components.first, protectedRoots.contains(root) {
            return Finding(risk: .high, reason: .systemWideDelete)
        }
        return nil
    }

    // MARK: - docker / git / izinler / veritabanı

    private static func dockerFinding(arguments: [String]) -> Finding? {
        let lowered = arguments.map { $0.lowercased() }
        guard lowered.contains("volume") || lowered.contains("system") else { return nil }

        if lowered.contains("prune") {
            let removesVolumes = lowered.contains("volume") || lowered.contains("--volumes")
            return removesVolumes ? Finding(risk: .high, reason: .dockerVolumeRemoval) : nil
        }
        if lowered.contains("volume"), lowered.contains("rm") || lowered.contains("remove") {
            return Finding(risk: .caution, reason: .dockerVolumeRemoval)
        }
        return nil
    }

    private static func gitFinding(arguments: [String]) -> Finding? {
        let lowered = arguments.map { $0.lowercased() }
        if lowered.contains("reset"), lowered.contains("--hard") {
            return Finding(risk: .caution, reason: .discardsLocalWork)
        }
        if lowered.contains("clean"), lowered.contains(where: isForceFlag) {
            return Finding(risk: .caution, reason: .discardsLocalWork)
        }
        return nil
    }

    private static func permissionFinding(arguments: [String]) -> Finding? {
        guard arguments.contains(where: isRecursiveFlag) else { return nil }
        // İlk bayrak olmayan argüman moddur (`777`) ya da sahiptir (`root`); hedef sonrasıdır.
        let targets = Array(arguments.filter { !$0.hasPrefix("-") }.dropFirst())
        let protected = targets.contains { target in
            deleteFinding(forTarget: target)?.reason == .systemWideDelete
        }
        return protected ? Finding(risk: .high, reason: .protectedPermissionChange) : nil
    }

    private static func databaseFinding(head: String, arguments: [String], text: String) -> Finding? {
        // Metni yalnız YAZDIRAN komutlar taranmaz; `echo "DROP DATABASE …"` uyarı değildir.
        guard !readOnlyCommands.contains(head) else { return nil }
        if head == "dropdb" { return Finding(risk: .high, reason: .databaseDrop) }
        if databaseDropMarkers.contains(where: { text.contains($0) }) {
            return Finding(risk: .high, reason: .databaseDrop)
        }
        let lowered = Set(arguments.map { $0.lowercased() })
        return lowered.isDisjoint(with: databaseDropSubcommands)
            ? nil
            : Finding(risk: .high, reason: .databaseDrop)
    }

    // MARK: - SSH

    private static func remoteWarning(arguments: [String]) -> DangerousCommandWarning? {
        var index = 0
        while index < arguments.count, arguments[index].hasPrefix("-") {
            index += sshOptionsWithValue.contains(arguments[index]) ? 2 : 1
        }
        // Hedef yoksa ya da hedeften sonra komut yoksa bu yalnızca bir oturum açmadır.
        guard index < arguments.count else { return nil }
        let remote = arguments.dropFirst(index + 1).joined(separator: " ")
        guard !remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return warnings(in: remote, isRemote: true).max { $0.risk < $1.risk }
    }

    // MARK: - Sözlükler

    private static let workingDirectoryTargets: Set<String> = [".", "./", "..", "../", "*", "./*", ".*"]
    private static let homeTargets: Set<String> = ["~", "~/", "~/*", "$HOME", "${HOME}", "$HOME/", "$HOME/*"]
    private static let homePrefixes = ["~/", "$HOME/", "${HOME}/"]
    /// Derinliğe bakılmaksızın korunan kökler (aygıtlar ve sistem çekirdeği).
    private static let protectedRoots: Set<String> = ["System", "private", "dev", "bin", "sbin"]
    private static let diskFormattingSubcommands: Set<String> = [
        "erasedisk", "erasevolume", "zerodisk", "partitiondisk", "reformat", "eraseoptical", "secureerase",
    ]
    private static let databaseDropMarkers = ["drop database", "drop schema", "dropdatabase("]
    private static let databaseDropSubcommands: Set<String> = [
        "migrate:fresh", "migrate:reset", "db:wipe", "db:drop", "db:reset",
    ]
    private static let readOnlyCommands: Set<String> = [
        "echo", "printf", "cat", "grep", "egrep", "fgrep", "rg", "less", "more", "head", "tail",
    ]
    /// Bu bayraklar bir DEĞER alır; `ssh -p 2222 host` çözümlenirken atlanmalıdır.
    private static let sshOptionsWithValue: Set<String> = [
        "-p", "-i", "-o", "-l", "-L", "-R", "-D", "-J", "-F", "-b", "-c", "-E", "-e", "-m", "-Q", "-S", "-W", "-w",
    ]
    /// Asıl komutun önüne geçen sarmalayıcılar.
    private static let wrapperCommands: Set<String> = [
        "sudo", "doas", "env", "nohup", "time", "command", "xargs", "nice", "stdbuf",
    ]

    // MARK: - Ayrıştırma yardımcıları

    private static func isRecursiveFlag(_ argument: String) -> Bool {
        if argument == "--recursive" { return true }
        guard argument.hasPrefix("-"), !argument.hasPrefix("--") else { return false }
        return argument.dropFirst().contains { $0 == "r" || $0 == "R" }
    }

    private static func isForceFlag(_ argument: String) -> Bool {
        if argument == "--force" { return true }
        guard argument.hasPrefix("-"), !argument.hasPrefix("--") else { return false }
        return argument.dropFirst().contains("f")
    }

    private static func isDeviceOutput(_ argument: String) -> Bool {
        let lowered = argument.lowercased()
        guard lowered.hasPrefix("of=") else { return false }
        return lowered.dropFirst(3).hasPrefix("/dev/")
    }

    private static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { $0 != "*" && $0 != "." }
    }

    private static func pathDepth(_ path: String) -> Int { pathComponents(path).count }

    /// `/bin/rm` → `rm`. Tam yolla çağrılan komut da tanınmalı.
    private static func commandName(_ token: String) -> String {
        (token as NSString).lastPathComponent.lowercased()
    }

    /// `sudo`, `env FOO=bar`, `xargs` gibi sarmalayıcılar atılır; geriye asıl komut kalır.
    private static func strippingWrappers(_ tokens: [String]) -> [String] {
        var remaining = tokens[...]
        var strippedWrapper = false

        while let first = remaining.first {
            if wrapperCommands.contains(commandName(first)) {
                strippedWrapper = true
                remaining = remaining.dropFirst()
                continue
            }
            // `FOO=bar cmd` — komuttan önceki ortam ataması.
            if isEnvironmentAssignment(first) {
                remaining = remaining.dropFirst()
                continue
            }
            // Sarmalayıcının kendi bayrakları (`env -i`, `nice -n 10`).
            if strippedWrapper, first.hasPrefix("-") {
                remaining = remaining.dropFirst()
                continue
            }
            break
        }

        return Array(remaining)
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let separator = token.firstIndex(of: "="), separator != token.startIndex else { return false }
        let name = token[token.startIndex..<separator]
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Tırnak farkındalıklı bölme: `&&`, `||`, `|`, `;`, `&` ve satır sonları ayraçtır.
    /// Tırnak içi bölünmez, yoksa `ssh host "cd /tmp && rm -rf /"` parçalanırdı.
    private static func segments(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
                index = text.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                index = text.index(after: index)
                continue
            }

            if character == ";" || character == "\n" || character == "|" || character == "&" {
                result.append(current)
                current = ""
                let next = text.index(after: index)
                // `&&` ve `||` tek ayraçtır.
                index = (next < text.endIndex && text[next] == character) ? text.index(after: next) : next
                continue
            }

            current.append(character)
            index = text.index(after: index)
        }

        result.append(current)
        return result
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Tırnak farkındalıklı sözcüklere ayırma; tırnaklar sonuçtan düşer.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var started = false
        var quote: Character?

        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                started = true
                continue
            }
            if character.isWhitespace {
                if started { tokens.append(current) }
                current = ""
                started = false
                continue
            }
            current.append(character)
            started = true
        }

        if started { tokens.append(current) }
        return tokens
    }
}

/// Uyarının ağırlığı. Renk TEK gösterge olamaz (briefs/2 "Erişilebilirlik"): her seviye
/// kendi sözcüğünü ve kendi şeklini taşır, renk üçüncü sinyaldir.
enum CommandRisk: Int, CaseIterable, Comparable {
    case caution = 1
    case high = 2

    var label: String {
        switch self {
        case .caution: "Destructive"
        case .high: "High risk"
        }
    }

    var symbolName: String {
        switch self {
        case .caution: "exclamationmark.triangle.fill"
        case .high: "exclamationmark.octagon.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .caution: "Destructive command"
        case .high: "High risk command"
        }
    }

    var colorToken: DesignTokens.ColorToken {
        switch self {
        case .caution: DesignTokens.warning
        case .high: DesignTokens.danger
        }
    }

    static func < (lhs: CommandRisk, rhs: CommandRisk) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Uyarının GEREKÇESİ — kullanıcıya "neden" sorusunun cevabı verilir, yalnız "dikkat" değil.
enum DangerousCommandReason: String, CaseIterable {
    case systemWideDelete
    case workingDirectoryDelete
    case remoteBulkDelete
    case diskFormat
    case rawDeviceWrite
    case databaseDrop
    case dockerVolumeRemoval
    case discardsLocalWork
    case protectedPermissionChange

    var explanation: String {
        switch self {
        case .systemWideDelete: "Recursively deletes a system, home or root folder."
        case .workingDirectoryDelete: "Recursively deletes everything in the current folder."
        case .remoteBulkDelete: "Recursively deletes files on the remote host."
        case .diskFormat: "Erases or reformats a disk and everything stored on it."
        case .rawDeviceWrite: "Writes straight to a disk device and destroys its contents."
        case .databaseDrop: "Drops a database or wipes all of its tables."
        case .dockerVolumeRemoval: "Removes Docker volumes and the data stored in them."
        case .discardsLocalWork: "Discards uncommitted work in this repository."
        case .protectedPermissionChange: "Changes permissions or ownership of a protected system folder."
        }
    }
}

/// Tek bir uyarı: ne kadar ağır, neden, hangi alt komut yüzünden.
struct DangerousCommandWarning: Equatable {
    let risk: CommandRisk
    let reason: DangerousCommandReason
    /// Uyarıyı doğuran alt komut (zincirin tamamı değil).
    let command: String
    let isRemote: Bool

    /// Görünen açıklama.
    var message: String {
        isRemote ? "\(reason.explanation) It runs on the remote host." : reason.explanation
    }

    /// Görünen kısa etiket (simgeyle birlikte, renkten bağımsız).
    var label: String { risk.label }

    var symbolName: String { risk.symbolName }

    /// VoiceOver: seviye ve sonuç TEK cümlede duyulur.
    var accessibilityLabel: String { "\(risk.accessibilityLabel): \(message)" }
}
