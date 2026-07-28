import Foundation

/// Bir mesajın kimden geldiği. `rawValue`'lar Ollama'nın chat API'siyle aynıdır.
enum AIMessageRole: String, Codable, CaseIterable {
    case system
    case user
    case assistant
}

/// Panelde görünen tek mesaj.
///
/// Burada tutulan metin HAM'dır (kullanıcının yazdığı, modelin döndürdüğü). Maskeleme
/// yalnız DIŞARI çıkarken yapılır (`AIRequestBuilder`): kullanıcı kendi yazdığını
/// ekranda maskelenmiş görmemeli, ama gönderilen metin maskelenmiş olmalı.
struct AIMessage: Identifiable, Equatable {
    let id: UUID
    let role: AIMessageRole
    var text: String
    let date: Date

    init(id: UUID = UUID(), role: AIMessageRole, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

// MARK: - Konuşma

/// briefs/3 "AI Paneli" bölüm 1–2: konuşma başlığı ve mesaj geçmişi.
///
/// Konuşma DİSKE YAZILMAZ. briefs/2 "Gizlilik": terminal geçmişi buluta gönderilmez ve
/// Termora'nın kendi tercihlerinde de bir soru-cevap arşivi tutmaya gerek yok. Pencere
/// kapandığında konuşma da gider.
struct AIConversation: Equatable {

    /// Henüz soru sorulmamış konuşmanın başlığı.
    static let untitled = "New conversation"

    /// Başlık paneli germemeli; bu uzunluktan sonrası kesilir.
    static let titleLimit = 60

    let id: UUID
    private(set) var messages: [AIMessage] = []
    /// İlk sorudan türetilir ve BİR KEZ ayarlanır: sonraki sorular başlığı değiştirseydi
    /// panel başlığı her istekte zıplardı.
    private(set) var title: String = AIConversation.untitled

    init(id: UUID = UUID()) {
        self.id = id
    }

    mutating func append(_ message: AIMessage) {
        messages.append(message)
        guard title == Self.untitled, message.role == .user else { return }
        title = Self.title(from: message.text)
    }

    mutating func removeAll() {
        messages.removeAll()
        title = Self.untitled
    }

    /// Bir sonraki isteğe konacak geçmiş. Sistem yönergesi `AIRequestBuilder`'da kurulur,
    /// bu yüzden buradan çıkarılır — yoksa iki sistem mesajı gönderilirdi.
    var history: [AIMessage] {
        messages.filter { $0.role != .system }
    }

    private static func title(from text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return untitled }
        guard flattened.count > titleLimit else { return flattened }
        return flattened.prefix(titleLimit).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - Önerilen komut

/// AI'ın ürettiği tek komut. **Kendiliğinden çalışmaz**; briefs/2: "AI uygun shell
/// komutunu üretir ancak otomatik çalıştırmaz."
///
/// Risk incelemesi burada, ÜRETİM anında yapılır: uyarı komutun bir özelliğidir, düğmeye
/// basıldığında hesaplanan bir şey değil. Böylece kullanıcı Run'a uzanmadan ÖNCE görür.
struct AICommandSuggestion: Identifiable, Equatable {
    let id: UUID
    /// Blokta yazan komut, olduğu gibi (çok satırlı olabilir).
    let command: String
    /// `DangerousCommand` bulgusu; yoksa nil.
    let warning: DangerousCommandWarning?

    init(id: UUID = UUID(), command: String) {
        self.id = id
        self.command = command
        self.warning = Self.worstWarning(in: command)
    }

    var isRisky: Bool { warning != nil }

    /// Terminale YAZILACAK hâl.
    ///
    /// Çok satırlı bir blok olduğu gibi gönderilseydi aradaki her satır sonu birer
    /// "çalıştır" olurdu — yani Insert sessizce Run'a dönüşürdü. Satırlar `; ` ile
    /// birleştirilir: adımlar sırayla ve TEK onayla çalışır.
    ///
    /// Onay penceresi de bunu gösterir; kullanıcının okuduğu metinle çalışan metin aynıdır.
    var terminalText: String {
        command
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
    }

    /// Renkten bağımsız etiket ("Destructive" / "High risk").
    var riskLabel: String? { warning?.label }

    var riskSymbolName: String? { warning?.symbolName }

    /// VoiceOver: seviye ve sonuç tek cümlede duyulur.
    var riskAccessibilityLabel: String? { warning?.accessibilityLabel }

    /// Kırmızı uyarı alanının gövdesi (briefs/3: "Riskli komutlarda kırmızı uyarı alanı").
    var riskExplanation: String? { warning?.message }

    /// Çok satırlı bir blokta EN AĞIR satır kazanır: zararsız bir ilk satır (`echo …`)
    /// altındaki `rm -rf /`'i gizleyemez.
    private static func worstWarning(in command: String) -> DangerousCommandWarning? {
        command
            .components(separatedBy: "\n")
            .compactMap { DangerousCommand.inspect($0) }
            .max { $0.risk < $1.risk }
    }
}

/// Cevabın çizim birimi: düz metin ya da komut bloğu.
enum AIReplySegment: Identifiable, Equatable {
    case prose(id: UUID, text: String)
    case command(AICommandSuggestion)

    var id: UUID {
        switch self {
        case let .prose(id, _): id
        case let .command(suggestion): suggestion.id
        }
    }
}

/// Modelin cevabından komut bloklarını çıkarır.
///
/// # Neden yalnız kod bloğu
///
/// Serbest metinden komut tahmin etmek (satır `$` ile başlıyorsa komuttur gibi) yanlış
/// pozitif üretir ve kullanıcıya çalıştırılabilir görünen ama komut olmayan bir düğme
/// verir. Sistem yönergesi modele komutu kod bloğuna koymasını söyler; ayrıştırıcı da
/// yalnız onu tanır.
///
/// # Neden yalnız kabuk dilleri
///
/// ` ```json ` bloğu bir komut değildir. Ona Run düğmesi vermek, kullanıcıyı bir dosya
/// içeriğini terminale yapıştırmaya davet etmek olurdu.
enum AIReplyParser {

    /// Komut sayılan blok bilgileri. Boş bilgi (` ``` `) de kabul edilir: modeller sık sık
    /// dili yazmaz.
    private static let shellLanguages: Set<String> = [
        "", "sh", "bash", "zsh", "shell", "shellsession", "shell-session",
        "console", "terminal", "fish", "command", "cmd",
    ]

    private static let fence = "```"

    static func suggestions(in reply: String) -> [AICommandSuggestion] {
        segments(in: reply).compactMap {
            if case let .command(suggestion) = $0 { return suggestion }
            return nil
        }
    }

    /// Cevabı sırayı BOZMADAN düz metin ve komut parçalarına ayırır.
    static func segments(in reply: String) -> [AIReplySegment] {
        let lines = reply.components(separatedBy: "\n")
        var segments: [AIReplySegment] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            prose.removeAll()
            guard !text.isEmpty else { return }
            segments.append(.prose(id: UUID(), text: text))
        }

        while index < lines.count {
            let line = lines[index]
            guard let language = fenceLanguage(line) else {
                prose.append(line)
                index += 1
                continue
            }

            guard let close = lines[(index + 1)...].firstIndex(where: { isClosingFence($0) }) else {
                // Kapanışı olmayan blok: geri kalan METİNDİR. Yarım bir bloğu komut saymak,
                // modelin cevabı kesildiğinde eksik bir komuta Run düğmesi vermek olurdu.
                prose.append(contentsOf: lines[index...])
                index = lines.count
                continue
            }

            let body = lines[(index + 1)..<close]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            index = close + 1

            guard shellLanguages.contains(language), !body.isEmpty else {
                // Kabuk olmayan blok da cevabın parçasıdır; metin olarak korunur.
                prose.append(contentsOf: [fence + language, body, fence])
                continue
            }
            flushProse()
            segments.append(.command(AICommandSuggestion(command: body)))
        }

        flushProse()
        return segments
    }

    /// Açılış çiti ise dil bilgisini (küçük harfle) döndürür.
    private static func fenceLanguage(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(fence) else { return nil }
        return String(trimmed.dropFirst(fence.count))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    private static func isClosingFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == fence
    }
}

// MARK: - Eylemler

/// briefs/3 "AI Paneli": üretilen komutlarda bulunması gereken eylemler.
enum AICommandAction: String, CaseIterable, Identifiable {
    case copy
    case insert
    case explain
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: "Copy"
        case .insert: "Insert"
        case .explain: "Explain"
        case .run: "Run"
        }
    }

    var symbolName: String {
        switch self {
        case .copy: "doc.on.doc"
        case .insert: "text.insert"
        case .explain: "questionmark.circle"
        case .run: "play.fill"
        }
    }

    /// VoiceOver: "Copy" tek başına neyi kopyaladığını söylemez.
    var accessibilityLabel: String {
        switch self {
        case .copy: "Copy command to the clipboard"
        case .insert: "Insert command into the terminal without running it"
        case .explain: "Ask what this command does"
        case .run: "Run command after confirmation"
        }
    }

    /// briefs/3: "`Run` işlemi kullanıcı onayı olmadan çalışmamalıdır." Diğer üç eylem
    /// hiçbir şey çalıştırmaz — Insert bile komutu yalnız yazar, Enter'a basmaz.
    var needsConfirmation: Bool { self == .run }
}

/// Run onayının TÜM metni.
///
/// Onay bir `confirmationDialog`'dur: orada renk, kalınlık ya da SF Symbol YOKTUR.
/// Bu yüzden risk işareti metnin içine girer (simge karakteri + seviyeyi adlandıran söz),
/// tıpkı workspace başlangıç komutlarında olduğu gibi.
enum AIRunPrompt {
    static let title = "Run this command?"

    /// Belirsiz "OK"/"Yes" yok (briefs/3 "Uygulama Metin Dili").
    static let confirmTitle = "Run Command"
    static let cancelTitle = "Cancel"
    static let allButtonTitles = [confirmTitle, cancelTitle]

    static let riskMarker = "⚠"

    /// Onay metni, terminale DÜŞECEK satırı gösterir (çok satırlı öneri `;` ile
    /// birleşmiş hâliyle) — kullanıcı okuduğu şeyi onaylar.
    static func message(for command: String) -> String {
        let suggestion = AICommandSuggestion(command: command)
        let body = "Termora will type this into the active terminal and press return:"
            + "\n\n\(suggestion.terminalText)"
        guard let warning = suggestion.warning else { return body }
        return "\(riskMarker) \(warning.label) — \(warning.message)\n\n\(body)"
    }
}
