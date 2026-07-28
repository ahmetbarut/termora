import Foundation

/// briefs/2 "Secret Maskeleme": AI'a (ya da herhangi bir dış hedefe) metin gönderilmeden
/// önce hassas değerler maskelenir.
///
/// # Tasarım kararları
///
/// **Saf.** Girdi metin, çıktı maskelenmiş metin + NE maskelendiğinin dökümü. Ağ, disk ve
/// durum yok; böylece AI katmanı gelmeden önce burada karar verilir ve testlenir.
///
/// **Yanlış negatif, yanlış pozitiften tehlikelidir.** Kararsız kalınan yerde maskelenir:
/// adı sır söyleyen bir değişkenin değeri (`DB_PASSWORD=…`) içeriğine bakılmadan gizlenir.
///
/// **Ama aşırı maskeleme çıktıyı işe yaramaz hâle getirir.** Çizgi şurada çekilir:
/// - Değer bazlı kurallar yalnız TANINAN biçimlere bakar (AWS/GitHub/JWT/`sk-…` önekleri,
///   `Bearer`, `Authorization`, URL parolası). Rastgele uzun dizeler maskelenmez.
/// - Ad bazlı kural yalnız adı sır söyleyen atamaları gizler. `PATH=/usr/bin`,
///   `NODE_ENV=production` gibi zararsız satırlara dokunulmaz.
/// - `*_PATH`, `*_FILE`, `*_DIR` gibi YOL adları sır değildir; yol maskelenirse hata
///   ayıklama imkânsızlaşır, üstelik yolun kendisi bir anahtar taşımaz.
/// - Değer bir kabuk değişkeni referansıysa (`$TOKEN`, `${TOKEN}`) maskelenmez: zaten
///   sırrı sızdırmaz, ama komutun ne yaptığını anlatır.
///
/// **Maskeleme sırrın uzunluğunu sızdırmaz**: her sır sabit `[REDACTED]` ile değiştirilir.
enum SecretMasker {

    /// Sabit yer tutucu — uzunluk sızdırmaz (6 karakterlik parola ile 64 karakterlik
    /// anahtar aynı görünür).
    static let placeholder = "[REDACTED]"

    static let noSecretsSummary = "No secrets found in this text."

    /// Metni maskeler ve kullanıcının inceleyebilmesi için ne yapıldığını raporlar
    /// (briefs/2: "Kullanıcı gönderilecek son içeriği inceleyebilmelidir").
    static func mask(_ text: String) -> SecretMaskingResult {
        guard !text.isEmpty else { return SecretMaskingResult(maskedText: text, findings: []) }

        // Satır satır ilerlenir: private key BLOKLARI tek parça hâlinde tüketilir, geri
        // kalan satırlara değer/ad kuralları uygulanır. Satır numaraları ORİJİNAL metne
        // aittir — blok birden çok satırı yutsa bile bulgu doğru satırı gösterir.
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        output.reserveCapacity(lines.count)
        var findings: [SecretFinding] = []

        var index = 0
        while index < lines.count {
            let line = lines[index]

            if isPrivateKeyBlockStart(line) {
                var end = index
                while end < lines.count, !lines[end].contains(privateKeyEndMarker) { end += 1 }
                // Kapanışı olmayan blok metnin SONUNA kadar maskelenir: yarım kalmış bir
                // anahtar da anahtardır.
                findings.append(SecretFinding(kind: .privateKeyBlock, line: index + 1))
                output.append(placeholder)
                index = min(end, lines.count - 1) + 1
                continue
            }

            let (masked, kinds) = maskLine(line)
            output.append(masked)
            findings.append(contentsOf: kinds.map { SecretFinding(kind: $0, line: index + 1) })
            index += 1
        }

        return SecretMaskingResult(maskedText: output.joined(separator: "\n"), findings: findings)
    }

    // MARK: - Private key blokları

    /// Blok, `-----BEGIN … PRIVATE KEY-----` ile `-----END …` arasındaki HER ŞEYDİR;
    /// satır satır değil bütün olarak maskelenir. `PUBLIC KEY` sır değildir, eşleşmez.
    private static func isPrivateKeyBlockStart(_ line: String) -> Bool {
        guard let regex = privateKeyBeginRegex else { return false }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }

    private static let privateKeyBeginRegex = try? NSRegularExpression(
        pattern: "-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----"
    )

    private static let privateKeyEndMarker = "-----END"

    // MARK: - Satır kuralları

    /// Bir kuralın tanımı. `valueGroup` maskelenecek yakalama grubudur; grubun DIŞINDA
    /// kalan her şey (başlık adı, `Bearer` şeması, URL'nin host kısmı…) korunur —
    /// maskelenmiş çıktı hâlâ okunabilir olmalıdır.
    private struct RuleSpec {
        let kind: SecretKind
        let pattern: String
        let valueGroup: Int
        /// Doluysa: yalnız ADI sır söyleyen atamalar maskelenir.
        var nameGroup: Int?
    }

    private struct Rule {
        let kind: SecretKind
        let regex: NSRegularExpression
        let valueGroup: Int
        let nameGroup: Int?
    }

    /// Sıra önemlidir: önce özel (şema/başlık koruyan) kurallar, sonra genel ad kuralı.
    /// Böylece `Authorization: Bearer …` satırında `Bearer` ayakta kalır ve bulgu
    /// "Authorization header" olarak raporlanır.
    private static let ruleSpecs: [RuleSpec] = [
        // 1. Authorization / Proxy-Authorization: şema korunur, kimlik bilgisi gider.
        //    Değer tırnakta biter, böylece `curl -H "…" https://…` satırında URL korunur.
        RuleSpec(kind: .authorizationHeader,
                 pattern: #"(?i)\b(?:proxy-)?authorization"?\s*:\s*"?(?:(?:bearer|basic|token|digest|apikey|aws4-hmac-sha256)\s+)?([^"'\n]*[^"'\s\n])"#,
                 valueGroup: 1),

        // 2. Cookie / Set-Cookie: değerin tamamı gider (tek tek çerezleri ayıklamak
        //    kazanç sağlamaz, session çerezi zaten oturumun kendisidir).
        RuleSpec(kind: .cookie,
                 pattern: #"(?i)\b(?:set-)?cookie"?\s*:\s*"?([^"'\n]*[^"'\s\n])"#,
                 valueGroup: 1),

        // 3. Anahtar taşıyan diğer başlıklar.
        RuleSpec(kind: .apiKey,
                 pattern: #"(?i)\b(?:x-api-key|api-key|apikey|x-auth-token|auth-token|x-access-token|x-csrf-token|x-session-token|private-token|x-amz-security-token)"?\s*:\s*"?([^"'\n]*[^"'\s\n])"#,
                 valueGroup: 1),

        // 4. Başlık dışında geçen `Bearer <token>`. Yalnız `Bearer`: `Basic` sözcüğü
        //    günlük metinde de geçer, `Bearer` geçmez — yanlış pozitif riski düşük.
        RuleSpec(kind: .bearerToken,
                 pattern: #"(?i)\bbearer\s+([A-Za-z0-9\-._~+/=]{6,})"#,
                 valueGroup: 1),

        // 5. URL içindeki parola: host, kullanıcı ve yol korunur, yalnız parola gider.
        RuleSpec(kind: .urlPassword,
                 pattern: #"\b[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s:/@]+:([^\s@/]+)@"#,
                 valueGroup: 1),

        // 6. AWS erişim anahtarı kimliği (sabit önek + 16 karakter).
        RuleSpec(kind: .awsAccessKey,
                 pattern: #"\b((?:AKIA|ASIA|ABIA|ACCA|AIDA|AROA|ANPA|ANVA)[A-Z0-9]{16})\b"#,
                 valueGroup: 1),

        // 7. GitHub token'ları (klasik ve fine-grained).
        RuleSpec(kind: .githubToken,
                 pattern: #"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#,
                 valueGroup: 1),

        // 8. JWT: üç noktalı parça, `eyJ` ile başlar. Oturum/erişim jetonlarının yaygın biçimi.
        RuleSpec(kind: .jsonWebToken,
                 pattern: #"\b(eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,})"#,
                 valueGroup: 1),

        // 9. Sağlayıcı önekli anahtarlar. Önek listesi bilinçli olarak DAR tutulur:
        //    "uzun rastgele dize" gibi bir kural bütün çıktıyı maskelerdi.
        RuleSpec(kind: .apiKey,
                 pattern: #"\b((?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{6,}|sk-[A-Za-z0-9][A-Za-z0-9_-]{5,}|xox[abposr]-[A-Za-z0-9-]{8,}|AIza[A-Za-z0-9_-]{20,}|glpat-[A-Za-z0-9_-]{10,}|npm_[A-Za-z0-9]{20,}|dop_v1_[A-Za-z0-9]{20,}|SG\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})"#,
                 valueGroup: 1),

        // 10. Komut satırı bayrakları. Yalnız UZUN bayraklar: `-p` gibi tek harfli bayraklar
        //     her araçta başka anlama gelir (`mkdir -p`), yüksek güvenle tespit edilemez.
        RuleSpec(kind: .commandLineSecret,
                 pattern: #"(?i)--(?:password|passwd|token|api-key|apikey|secret|access-key|auth-token|client-secret|private-token)(?:\s*=\s*|\s+)"?([^\s"'\n]+)"#,
                 valueGroup: 1),

        // 11. Satırın tamamı bir atama: `.env` dosyaları ve `export` satırları.
        //     Değer boşluk içerebilir, bu yüzden satır sonuna kadar alınır.
        RuleSpec(kind: .environmentValue,
                 pattern: #"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.\-]*)\s*=\s*(.+?)\s*$"#,
                 valueGroup: 2,
                 nameGroup: 1),

        // 12. Satır içi atama: `env DB_PASSWORD=… ./run.sh`.
        RuleSpec(kind: .environmentValue,
                 pattern: #"(?:^|[\s;&|(])(?:export\s+)?([A-Za-z_][A-Za-z0-9_.\-]*)=("[^"\n]*"|'[^'\n]*'|[^\s;&|)\n]+)"#,
                 valueGroup: 2,
                 nameGroup: 1),

        // 13. `ad: değer` biçimi (YAML, JSON, log satırları).
        RuleSpec(kind: .environmentValue,
                 pattern: #""?\b([A-Za-z_][A-Za-z0-9_.\-]*)"?\s*:\s*"?([^"',\n]*[^"',\s\n])"#,
                 valueGroup: 2,
                 nameGroup: 1),
    ]

    private static let rules: [Rule] = ruleSpecs.compactMap { spec in
        guard let regex = try? NSRegularExpression(pattern: spec.pattern) else { return nil }
        return Rule(kind: spec.kind, regex: regex, valueGroup: spec.valueGroup, nameGroup: spec.nameGroup)
    }

    /// Test kancası: bozuk bir desen sessizce KAYBOLMAMALI (briefs/2: "Hatalar sessizce
    /// yutulmamalı"). `SecretMaskerTests` iki sayının eşit olduğunu doğrular.
    static var compiledRuleCount: Int { rules.count }
    static var declaredRuleCount: Int { ruleSpecs.count }

    private static func maskLine(_ line: String) -> (String, [SecretKind]) {
        var current = line
        var kinds: [SecretKind] = []

        for rule in rules {
            let source = current as NSString
            let matches = rule.regex.matches(in: current,
                                             options: [],
                                             range: NSRange(location: 0, length: source.length))
            guard !matches.isEmpty else { continue }

            var updated = current
            var appliedCount = 0
            // Sondan başa: erken eşleşmelerin aralıkları geçerli kalır.
            for match in matches.reversed() {
                let valueRange = match.range(at: rule.valueGroup)
                guard valueRange.location != NSNotFound else { continue }

                if let nameGroup = rule.nameGroup {
                    let nameRange = match.range(at: nameGroup)
                    guard nameRange.location != NSNotFound,
                          isSecretName(source.substring(with: nameRange)) else { continue }
                }

                guard isMaskableValue(source.substring(with: valueRange)) else { continue }

                updated = (updated as NSString).replacingCharacters(in: valueRange, with: placeholder)
                appliedCount += 1
            }

            current = updated
            kinds.append(contentsOf: Array(repeating: rule.kind, count: appliedCount))
        }

        return (current, kinds)
    }

    // MARK: - Karar kuralları

    /// Maskelemenin bir şey KAZANDIRDIĞI durumlar. Yer tutucu içeren değer zaten
    /// maskelenmiştir (maskeleme bu sayede idempotenttir).
    private static func isMaskableValue(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(placeholder) else { return false }
        let unquoted = stripSurroundingQuotes(trimmed)
        guard !unquoted.isEmpty else { return false }
        // `$TOKEN` / `${TOKEN}`: sırrın kendisi değil, adı. Maskelemek bilgi kaybıdır.
        return !unquoted.hasPrefix("$")
    }

    private static func stripSurroundingQuotes(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Adın sır söyleyip söylemediği. Ad PARÇALARINA ayrılır ve tam sözcük aranır:
    /// `AUTHOR` yalnızca `auth` ile başladığı için maskelenmez, `OAUTH_TOKEN` maskelenir.
    private static func isSecretName(_ raw: String) -> Bool {
        let tokens = nameTokens(raw)
        // Son parça bir yol/dosya adıysa değer sır değil, yerdir.
        guard let last = tokens.last, !pathLikeTokens.contains(last) else { return false }
        return tokens.contains { secretNameTokens.contains($0) }
    }

    private static let secretNameTokens: Set<String> = [
        "password", "passwords", "passwd", "pwd", "passphrase",
        "secret", "secrets", "token", "tokens", "jwt", "bearer",
        "credential", "credentials", "auth", "authorization",
        "cookie", "session", "sessionid",
        "key", "keys", "apikey",
    ]

    private static let pathLikeTokens: Set<String> = [
        "path", "file", "filename", "dir", "directory", "folder", "location",
    ]

    /// `DB_PASSWORD` → ["db", "password"], `apiKey` → ["api", "key"],
    /// `DBPassword` → ["db", "password"].
    private static func nameTokens(_ raw: String) -> [String] {
        var tokens: [String] = []

        for chunk in raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let characters = Array(chunk)
            var current = ""

            for (offset, character) in characters.enumerated() {
                let previous = offset > 0 ? characters[offset - 1] : nil
                let next = offset + 1 < characters.count ? characters[offset + 1] : nil
                var startsNewWord = false
                if let previous, character.isUppercase {
                    if previous.isLowercase || previous.isNumber {
                        startsNewWord = true
                    } else if previous.isUppercase, let next, next.isLowercase {
                        startsNewWord = true
                    }
                }
                if startsNewWord, !current.isEmpty {
                    tokens.append(current.lowercased())
                    current = ""
                }
                current.append(character)
            }

            if !current.isEmpty { tokens.append(current.lowercased()) }
        }

        return tokens
    }
}

/// Maskelenen değerin TÜRÜ. Kullanıcıya ne saklandığını anlatır; değerin kendisi
/// hiçbir yerde taşınmaz.
enum SecretKind: String, CaseIterable {
    case privateKeyBlock
    case authorizationHeader
    case bearerToken
    case cookie
    case awsAccessKey
    case githubToken
    case apiKey
    case jsonWebToken
    case urlPassword
    case environmentValue
    case commandLineSecret

    /// Cümle içinde geçtiği için küçük harfle başlar; özel adlar (AWS, GitHub) korunur.
    var displayName: String {
        switch self {
        case .privateKeyBlock: "private key block"
        case .authorizationHeader: "Authorization header"
        case .bearerToken: "Bearer token"
        case .cookie: "cookie value"
        case .awsAccessKey: "AWS access key"
        case .githubToken: "GitHub token"
        case .apiKey: "API key"
        case .jsonWebToken: "JSON Web Token"
        case .urlPassword: "URL password"
        case .environmentValue: "environment value"
        case .commandLineSecret: "command-line secret"
        }
    }

    var pluralName: String { displayName + "s" }
}

/// Tek bir maskeleme bulgusu: NE ve NEREDE. Değerin kendisi bilinçli olarak tutulmaz —
/// bulgu listesi loglansa bile sır sızmaz (briefs/2: "Hassas veriler loglanmamalı").
struct SecretFinding: Hashable {
    let kind: SecretKind
    /// Orijinal metindeki 1 tabanlı satır numarası.
    let line: Int
}

/// Maskelemenin sonucu: gönderilecek metin + kullanıcının inceleyebileceği döküm.
struct SecretMaskingResult: Equatable {
    let maskedText: String
    let findings: [SecretFinding]

    var didFindSecrets: Bool { !findings.isEmpty }

    /// Kullanıcıya gösterilen tek satırlık özet, ör.
    /// "3 secrets hidden: 2 environment values, 1 Authorization header".
    var summary: String {
        guard !findings.isEmpty else { return SecretMasker.noSecretsSummary }

        var counts: [SecretKind: Int] = [:]
        for finding in findings { counts[finding.kind, default: 0] += 1 }

        let parts = counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value
                    ? lhs.key.displayName < rhs.key.displayName
                    : lhs.value > rhs.value
            }
            .map { Pluralize.count($0.value, $0.key.displayName, plural: $0.key.pluralName) }

        return "\(Pluralize.count(findings.count, "secret")) hidden: \(parts.joined(separator: ", "))"
    }
}
