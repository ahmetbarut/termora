import Foundation

// MARK: - Maskelenmiş yük

/// Termora'dan DIŞARI çıkabilen tek metin tipi.
///
/// # Neden bir tip
///
/// briefs/2 iki şey ister: hassas değerler AI'a gitmeden önce maskelenmeli ve kullanıcı
/// gönderilecek son içeriği görebilmeli. Bunu "her çağrı yerinde `SecretMasker.mask`
/// çağırmayı unutma" kuralıyla korumak, bir gün unutulacak bir kuraldır.
///
/// Bu yüzden kural TİPE gömüldü: `AIRequest` yalnız `MaskedPayload` taşır ve
/// `MaskedPayload`'ın başlatıcısı `fileprivate`'tır. Bu dosyanın DIŞINDA maskelenmemiş
/// bir dizeden `MaskedPayload` üretmenin yolu yoktur — tek kapı `masking(_:)`, o da
/// `SecretMasker`'dan geçer. İhlal test edilmez, DERLENMEZ.
///
/// `trusted(_:)` yalnız `StaticString` alır: derleme zamanı sabitleri sır taşıyamaz,
/// çalışma zamanı değeri o kapıdan geçemez.
struct MaskedPayload: Equatable {

    /// Gönderilecek metin. Maskelemeden GEÇMİŞTİR.
    let text: String

    /// Ne maskelendi (değerler değil, TÜRLERİ ve satırları). Kullanıcıya özet üretir.
    let findings: [SecretFinding]

    /// Bu dosyaya kapalıdır; bkz. tip yorumu.
    fileprivate init(text: String, findings: [SecretFinding]) {
        self.text = text
        self.findings = findings
    }

    /// Tek giriş kapısı: ham metin `SecretMasker`'dan geçer.
    static func masking(_ raw: String) -> MaskedPayload {
        let result = SecretMasker.mask(raw)
        return MaskedPayload(text: result.maskedText, findings: result.findings)
    }

    /// Derleme zamanı sabitleri (sistem yönergesi, bölüm başlıkları). `StaticString`
    /// olduğu için çalışma zamanında üretilmiş bir sır buraya sızamaz.
    static func trusted(_ literal: StaticString) -> MaskedPayload {
        MaskedPayload(text: literal.description, findings: [])
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// "2 secrets hidden: 1 API key, 1 URL password" ya da "No secrets found in this text."
    var maskingSummary: String {
        SecretMaskingResult(maskedText: text, findings: findings).summary
    }

    var didFindSecrets: Bool { !findings.isEmpty }
}

// MARK: - Bağlam türleri

/// briefs/2 "Terminal Bağlamı"nın saydığı bağlam parçaları.
///
/// Listede **tüm terminal geçmişi YOKTUR** ve bilerek yoktur: brief onu varsayılan olarak
/// yasaklıyor, Termora ise onu bir anahtarla değil YOKLUKLA garanti ediyor. Geçmişi
/// toplayan bir tür olmadığı için "yanlışlıkla açık kalmış" bir ayar da olamaz.
/// (`AIContextTests.thereIsNoWayToAskForTheWholeScrollback` bunu kilitler.)
///
/// Kullanıcının açıkça eklediği dosyalar brief'te sayılıyor ama bu turda YOK; dosya
/// eklemek bir dosya seçici ve boyut politikası ister, ikisi de brief'te tanımlı değil.
enum AIContextKind: String, CaseIterable, Codable, Identifiable {
    case selectedCommand
    case selectedOutput
    case workingDirectory
    case operatingSystem
    case shell
    case gitBranch

    var id: String { rawValue }

    /// Bağlam bloğunda ve inceleme listesinde görünen ad.
    var title: String {
        switch self {
        case .selectedCommand: "Selected command"
        case .selectedOutput: "Selected output"
        case .workingDirectory: "Working directory"
        case .operatingSystem: "Operating system"
        case .shell: "Shell"
        case .gitBranch: "Git branch"
        }
    }

    /// Kullanıcıya NEDEN gönderildiğini söyler. Ayarlardaki her anahtarın yanında durur —
    /// gizlilik kararı ancak gerekçesi bilinirse verilebilir.
    var purpose: String {
        switch self {
        case .selectedCommand:
            "The command you highlighted in the terminal, so the answer is about that command."
        case .selectedOutput:
            "The output you highlighted, so an error can be explained from what actually happened."
        case .workingDirectory:
            "The folder the active pane is in, so paths in a suggested command are correct."
        case .operatingSystem:
            "This Mac's name and version, so the answer avoids Linux-only flags."
        case .shell:
            "The shell the active pane runs, so the syntax matches zsh, bash or fish."
        case .gitBranch:
            "The branch the folder is on, so git advice matches where you are."
        }
    }

    /// Simge; renk tek gösterge olmadığı gibi simge de tek gösterge değildir (yanında
    /// her zaman `title` yazılır).
    var symbolName: String {
        switch self {
        case .selectedCommand: "chevron.left.forwardslash.chevron.right"
        case .selectedOutput: "text.alignleft"
        case .workingDirectory: "folder"
        case .operatingSystem: "desktopcomputer"
        case .shell: "terminal"
        case .gitBranch: "arrow.triangle.branch"
        }
    }
}

/// Hangi bağlam türlerinin gönderileceği. `AppSettings` içinde saklanır.
///
/// Alanlar tek tek `Bool` olarak yazıldı (sözlük değil): ileri uyumlu çözme her alanı
/// `decodeIfPresent` ile okur, ileride eklenen bir tür eski blobu bozmaz.
struct AIContextPreferences: Codable, Equatable {
    var includesSelectedCommand: Bool = true
    var includesSelectedOutput: Bool = true
    var includesWorkingDirectory: Bool = true
    var includesOperatingSystem: Bool = true
    var includesShell: Bool = true
    var includesGitBranch: Bool = true

    init() {}

    /// Elle yazılmış çözücü (proje kuralı): eksik anahtar varsayılana düşer, TÜM blob
    /// çöpe gitmez.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AIContextPreferences()
        includesSelectedCommand = try container.decodeIfPresent(Bool.self, forKey: .includesSelectedCommand)
            ?? defaults.includesSelectedCommand
        includesSelectedOutput = try container.decodeIfPresent(Bool.self, forKey: .includesSelectedOutput)
            ?? defaults.includesSelectedOutput
        includesWorkingDirectory = try container.decodeIfPresent(Bool.self, forKey: .includesWorkingDirectory)
            ?? defaults.includesWorkingDirectory
        includesOperatingSystem = try container.decodeIfPresent(Bool.self, forKey: .includesOperatingSystem)
            ?? defaults.includesOperatingSystem
        includesShell = try container.decodeIfPresent(Bool.self, forKey: .includesShell) ?? defaults.includesShell
        includesGitBranch = try container.decodeIfPresent(Bool.self, forKey: .includesGitBranch)
            ?? defaults.includesGitBranch
    }

    func includes(_ kind: AIContextKind) -> Bool {
        switch kind {
        case .selectedCommand: includesSelectedCommand
        case .selectedOutput: includesSelectedOutput
        case .workingDirectory: includesWorkingDirectory
        case .operatingSystem: includesOperatingSystem
        case .shell: includesShell
        case .gitBranch: includesGitBranch
        }
    }

    mutating func setIncludes(_ kind: AIContextKind, _ isIncluded: Bool) {
        switch kind {
        case .selectedCommand: includesSelectedCommand = isIncluded
        case .selectedOutput: includesSelectedOutput = isIncluded
        case .workingDirectory: includesWorkingDirectory = isIncluded
        case .operatingSystem: includesOperatingSystem = isIncluded
        case .shell: includesShell = isIncluded
        case .gitBranch: includesGitBranch = isIncluded
        }
    }
}

/// Terminalden okunan HAM bağlam. Maskeleme burada değil, `AIContextBuilder`'da yapılır;
/// böylece "ham" ve "gönderilecek" birbirine karışmaz.
struct AIContextSnapshot: Equatable {
    private(set) var values: [AIContextKind: String]

    init(_ values: [AIContextKind: String] = [:]) {
        self.values = values
    }

    subscript(kind: AIContextKind) -> String? {
        get { values[kind] }
        set { values[kind] = newValue }
    }

    var isEmpty: Bool { values.isEmpty }
}

/// Gönderilmeye hazır TEK bağlam satırı/bloğu. `value` maskelenmiştir.
struct AIContextEntry: Identifiable, Equatable {
    let kind: AIContextKind
    /// Maskelenmiş değer — kullanıcı listede tam olarak bunu görür.
    let value: String
    let findings: [SecretFinding]

    var id: String { kind.rawValue }

    var didFindSecrets: Bool { !findings.isEmpty }

    /// Çok satırlı değerler (seçili çıktı) kendi satırlarında durur; tek satırlıklar
    /// `Başlık: değer` biçiminde kalır ve panel listesi kompakt olur.
    var renderedText: String {
        value.contains("\n") ? "\(kind.title):\n\(value)" : "\(kind.title): \(value)"
    }
}

/// Kullanıcının istek ÖNCESİ inceleyebileceği son içerik (briefs/2).
struct PreparedAIContext: Equatable {
    let entries: [AIContextEntry]

    static let empty = PreparedAIContext(entries: [])

    var isEmpty: Bool { entries.isEmpty }

    var findings: [SecretFinding] { entries.flatMap(\.findings) }

    var didFindSecrets: Bool { !findings.isEmpty }

    var maskingSummary: String {
        SecretMaskingResult(maskedText: previewText, findings: findings).summary
    }

    /// Kullanıcıya gösterilen metin. İsteğin içine giren metnin BİREBİR aynısıdır —
    /// önizleme ayrı bir biçimlendirme değildir (`AIContextTests` bunu kilitler).
    var previewText: String {
        entries.map(\.renderedText).joined(separator: "\n")
    }

    /// İsteğe konacak yük. Parçalar zaten maskelenmiştir; burada yalnız birleştirilir,
    /// ikinci kez maskelenmez (maskeleme idempotent olsa da kullanıcıya gösterilen metnin
    /// bayt bayt aynısı gitmelidir).
    var payload: MaskedPayload {
        MaskedPayload(text: previewText, findings: findings)
    }
}

/// Ham anlık görüntüden gönderilebilir bağlama giden TEK yol.
enum AIContextBuilder {

    /// Seçimin gönderilebilecek en büyük boyu, karakter.
    ///
    /// # Neden bir sınır var
    ///
    /// briefs/2: "Tüm terminal geçmişi varsayılan olarak AI'a gönderilmemelidir."
    /// Seçim kullanıcının kendi eylemidir, ama ⌘A tek tuşta bütün scrollback'i seçer —
    /// sınır olmasaydı brief'in yasağı tek kısayolla delinirdi. Kesme burada, yani
    /// GÜVENLİK SINIRINDA yapılır; köprünün nazik davranmasına güvenilmez.
    static let selectionCharacterLimit = 4_000

    /// Kesildiğinde metnin başına konan işaret. Kullanıcı önizlemede bunu görür ve
    /// modelin neyi görmediğini bilir.
    static let truncationMarker = "[earlier lines omitted]"

    /// Kapalı türleri eler, boş değerleri atar, uzun seçimi kısaltır, kalanları maskeler.
    ///
    /// Sıra `AIContextKind.allCases`'tir: aynı bağlam her seferinde aynı sırayla görünür,
    /// böylece kullanıcı önizlemeyi okumayı öğrenir.
    static func prepare(_ snapshot: AIContextSnapshot,
                        preferences: AIContextPreferences) -> PreparedAIContext {
        let entries: [AIContextEntry] = AIContextKind.allCases.compactMap { kind in
            guard preferences.includes(kind) else { return nil }
            guard let raw = snapshot[kind]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            let bounded = truncated(raw)
            let masked = MaskedPayload.masking(bounded)
            return AIContextEntry(kind: kind, value: masked.text, findings: masked.findings)
        }
        return PreparedAIContext(entries: entries)
    }

    /// Sondan kesilir: bir komut başarısız olduğunda anlamlı satırlar ÇIKTININ SONUNDADIR
    /// (hata mesajı, exit kodu). Baştan kesmek tam da gereken kısmı atardı.
    private static func truncated(_ text: String) -> String {
        guard text.count > selectionCharacterLimit else { return text }
        return truncationMarker + "\n" + String(text.suffix(selectionCharacterLimit))
    }
}

// MARK: - İstek

/// İstekteki bir mesaj. İçerik `MaskedPayload`'dır: ham `String` alan bir başlatıcı YOKTUR.
struct AIRequestMessage: Equatable {
    let role: AIMessageRole
    let content: MaskedPayload
}

/// Sağlayıcıya gidecek istek. Ağ katmanı bundan başka bir şey kabul etmez.
struct AIRequest: Equatable {
    let model: String
    let messages: [AIRequestMessage]

    /// Dışarı çıkacak TÜM metin parçaları. Gizlilik denetimi (ve testler) bu listeye bakar;
    /// istek büyüdükçe listenin de büyümesi gerekir, yoksa denetim kör kalır.
    var outgoingTexts: [String] { messages.map(\.content.text) }
}

/// İsteği kuran tek yer.
enum AIRequestBuilder {

    /// Sistem yönergesi. Sabittir ve `StaticString`'tir: buradan kullanıcı verisi geçemez.
    ///
    /// İçeriği brief'ten gelir: komut üretilir ama ÇALIŞTIRILMAZ (briefs/2 "Komut Üretme"),
    /// riskli olan açıkça söylenir (briefs/2 "Tehlikeli Komut Koruması") ve komutlar
    /// ayrıştırılabilsin diye tek bir kod bloğunda verilir.
    static let systemPrompt: StaticString = """
        You are Termora's terminal assistant on macOS. Answer briefly and technically.
        When a shell command answers the question, put exactly that command in a fenced \
        code block and keep the explanation to a couple of sentences.
        Never claim to have run anything: Termora shows your command to the user and only \
        the user can run it.
        If a command destroys data or is hard to undo, say so in the sentence before it.
        Some values may appear as [REDACTED]; that is Termora hiding a secret. Do not ask \
        for the hidden value.
        """

    private static let contextHeader: StaticString = "Context from the user's terminal:"

    /// - Parameters:
    ///   - prompt: kullanıcının yazdığı metin. MASKELENİR — kullanıcı istemine sır
    ///     yapıştırmış olabilir ve o da dışarı giden metindir.
    ///   - history: eski mesajlar, ESKİDEN YENİYE.
    static func build(model: String,
                      prompt: String,
                      context: PreparedAIContext,
                      history: [AIMessage]) -> AIRequest {
        var messages: [AIRequestMessage] = [
            AIRequestMessage(role: .system, content: systemPayload(context: context))
        ]
        messages += history.map {
            AIRequestMessage(role: $0.role, content: MaskedPayload.masking($0.text))
        }
        messages.append(AIRequestMessage(role: .user, content: MaskedPayload.masking(prompt)))
        return AIRequest(model: model, messages: messages)
    }

    /// Bağlam, ikinci bir sistem mesajı olarak DEĞİL, tek sistem mesajının içinde gider:
    /// bazı modeller birden çok sistem mesajından yalnız ilkini dikkate alır.
    private static func systemPayload(context: PreparedAIContext) -> MaskedPayload {
        let instructions = MaskedPayload.trusted(systemPrompt)
        guard !context.isEmpty else { return instructions }
        let header = MaskedPayload.trusted(contextHeader)
        return MaskedPayload(
            text: [instructions.text, header.text, context.payload.text].joined(separator: "\n\n"),
            findings: context.findings
        )
    }
}
