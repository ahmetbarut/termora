import AppKit
import Foundation
import Observation

// MARK: - Terminal köprüsü

/// Panelin terminale bakan yüzü.
///
/// Panel `WorkspaceViewModel`'i ya da `SessionManager`'ı DOĞRUDAN tanımaz: tanısaydı
/// testler canlı bir PTY olmadan koşamazdı ve "Run onaysız çalışmaz" gibi bir kural
/// ancak gerçek bir shell açarak sınanabilirdi.
@MainActor
protocol AITerminalBridging: AnyObject {
    /// Aktif panelden okunabilen HAM bağlam. Maskeleme burada değil,
    /// `AIContextBuilder`'da yapılır.
    func captureContext() -> AIContextSnapshot
    /// Komutu terminal girişine yazar; return'e BASMAZ.
    func insert(_ text: String)
    /// Komutu yazar ve çalıştırır. Yalnız kullanıcı onayından sonra çağrılır.
    func run(_ command: String)
}

// MARK: - Ölçüler

/// briefs/3 "AI Paneli": varsayılan genişlik 360–420 pt.
enum AIPanelLayout {
    static let minWidth: CGFloat = 360
    static let maxWidth: CGFloat = 420
    /// Aralığın ortası: mesaj balonları rahat okunur, terminal hâlâ ana odaktır.
    static let defaultWidth: CGFloat = 390
}

// MARK: - Durumlar

/// Model listesinin durumu. `loading` GEÇİCİDİR: `refreshModels` her yolda bir sonuç
/// durumuna varır, bu yüzden panel sonsuz spinner gösteremez (briefs/3 "Loading State").
enum AIModelAvailability: Equatable {
    /// Panel henüz sunucuya sormadı — açılmadan ağ isteği yapılmaz.
    case idle
    case loading
    case ready([AIModel])
    case unavailable(AIProviderError)
}

enum AISendState: Equatable {
    case idle
    case sending
    case failed(AIProviderError)
}

/// briefs/3 "Error State"in dört sorusu tek yerde. Panel bunu çizer; metin üretmez.
struct AIPanelStatus: Equatable {
    let title: String
    let reason: String
    let recovery: String
    let technicalDetail: String

    init(_ error: AIProviderError) {
        title = error.title
        reason = error.reason
        recovery = error.recovery
        technicalDetail = error.technicalDetail
    }
}

// MARK: - Panel modeli

/// briefs/3 "AI Paneli" bölümlerinin durumu: konuşma başlığı, mesaj geçmişi, gönderilecek
/// bağlam göstergesi, prompt alanı, sağlayıcı/model seçimi.
///
/// # İki kırmızı çizgi
///
/// 1. **Hiçbir şey kendiliğinden çalışmaz.** `requestRun` yalnız onay penceresini açar;
///    terminale dokunan tek yol `confirmRun`'dır (briefs/2).
/// 2. **Hiçbir durum belirsiz bırakılmaz.** Model yoksa, sunucu kapalıysa ya da cevap
///    okunamazsa panel ne olduğunu, neden olduğunu ve ne yapılacağını yazar.
///
/// Konuşma pencere başınadır ve diske yazılmaz (briefs/2 "Gizlilik").
@MainActor
@Observable
final class AIPanelModel {

    /// Bağlam boşken gösterilen satır — boş bir kutu değil, cümle.
    static let emptyContextSummary = "No terminal context will be sent."

    // MARK: Bağımlılıklar

    private let provider: any AIProviding
    let settings: SettingsStore
    /// Model listesi Ayarlar ▸ AI ile PAYLAŞILAN mantıktır; bkz. `AIModelCatalog`.
    let catalog: AIModelCatalog

    /// Pencere kurulduğunda takılır. `nil` iken panel çizilir ama terminale dokunan
    /// eylemler hiçbir şey yapmaz (Ayarlar penceresinden açılan bir önizleme gibi).
    weak var bridge: (any AITerminalBridging)?

    /// Panoya yazma dikişi; testler gerçek panoyu kirletmemeli.
    var copyToClipboard: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Durum

    var isPresented = false
    var conversation = AIConversation()
    var prompt = ""
    private(set) var sendState: AISendState = .idle
    /// Gönderilecek son içerik. `refreshContext()` ile tazelenir; panel açıkken
    /// prompt alanının üstünde durur.
    private(set) var preparedContext: PreparedAIContext = .empty
    /// Bağlam listesinin açık olup olmadığı (briefs/2: kullanıcı son içeriği inceleyebilmeli).
    var isContextExpanded = false
    /// Akış sürerken ekranda duran CANLI metin; akış bitince ya da düşünce nil olur.
    /// Konuşmaya yazılmaz — komut önerileri yalnız TAMAMLANMIŞ mesajdan çıkarılır.
    private(set) var streamingText: String?

    /// Her parça geldiğinde çağrılır. Test dikişi: akış SÜRERKEN modelin ne durumda
    /// olduğunu gözlemeyi mümkün kılar.
    var onStreamDelta: (() -> Void)?

    /// Kullanıcının açıkça eklediği dosyalar (briefs/2 "Terminal Bağlamı").
    /// Pencere başınadır ve diske YAZILMAZ — konuşmayla aynı kural.
    private(set) var attachments: [AIFileAttachment] = []

    /// Son ekleme denemesinin başarısızlığı; kullanıcı neden eklenemediğini görür.
    private(set) var attachmentFailure: String?

    /// Dosya seçme dikişi. Testler gerçek bir panel açmaz.
    var chooseFiles: () -> [URL] = { AIFilePicker.chooseFiles() }

    /// Diskten okuma dikişi.
    var readFile: (URL) throws -> Data = { try Data(contentsOf: $0) }

    /// Komut alanına odak isteği (briefs/2 "AI komut alanını açma"). Panel görünümü bu
    /// jetonu görünce `@FocusState`'i kurar. Her istekte YENİLENİR: panel zaten açıkken
    /// komutu tekrar çağırmak da imleci yazma alanına götürmeli.
    private(set) var promptFocusRequest: UUID?

    /// Onay bekleyen komut. Doluyken terminale HİÇBİR ŞEY yazılmamıştır.
    private(set) var pendingRun: AICommandSuggestion?

    /// - Parameter catalog: verilmezse kendi kataloğunu kurar. Üretimde `AppServices`'in
    ///   kataloğu geçirilir; aksi hâlde Ayarlar ▸ AI ile panel AYRI listelere bakar ve
    ///   biri "model yok" derken diğeri hiçbir şey söylemez (görsel doğrulamada yakalandı).
    init(provider: any AIProviding, settings: SettingsStore, catalog: AIModelCatalog? = nil) {
        self.provider = provider
        self.settings = settings
        self.catalog = catalog ?? AIModelCatalog(provider: provider, settings: settings)
    }

    // MARK: - Model seçimi

    var availability: AIModelAvailability { catalog.availability }

    var selectedModel: String? {
        get { catalog.selectedModel }
        set { catalog.selectedModel = newValue }
    }

    var installedModels: [AIModel] { catalog.installedModels }

    var providerName: String { catalog.providerName }

    var endpointDescription: String { catalog.endpointDescription }

    /// Gösterilecek hata; hata yoksa nil. Model listesi ve gönderim hataları AYNI yerden
    /// okunur, böylece panelde iki ayrı hata alanı olmaz. Gönderim hatası önceliklidir:
    /// kullanıcının az önce yaptığı şeyle ilgilidir.
    var status: AIPanelStatus? {
        if case let .failed(error) = sendState { return AIPanelStatus(error) }
        return catalog.status
    }

    var isBusy: Bool {
        catalog.isLoading || sendState == .sending
    }

    /// Kurulu modelleri sorar. Her yolda sonuç durumuna varır — `loading`'de kalmaz.
    func refreshModels() async {
        await catalog.refresh()
    }

    /// Panel HİÇ açılmadan menüden bir eylem tetiklendiğinde ilk hazırlık.
    /// Model listesi daha önce sorulmadıysa şimdi sorulur; sorulduysa ağa çıkılmaz.
    func prepareIfNeeded() async {
        guard availability == .idle else { return }
        await refreshModels()
    }

    /// Menüden "Explain Selection with AI": paneli açar, bağlamı tazeler ve sorar.
    /// Paneli açar ve imleci komut alanına götürür. Yalnız açmak, kullanıcıyı klavyeden
    /// fareye gönderirdi — brief "komut alanını açma" diyor, "paneli gösterme" değil.
    func openPromptField() {
        isPresented = true
        promptFocusRequest = UUID()
    }

    func openAndExplainSelection() async {
        isPresented = true
        await prepareIfNeeded()
        refreshContext()
        await explainSelection()
    }

    // MARK: - Bağlam

    /// Terminalden bağlamı okur, tercihlerden geçirir ve MASKELER.
    /// Panel açılırken, aktif panel değişince ve gönderim öncesi çağrılır.
    /// briefs/2 "Kullanıcının açıkça eklediği dosyalar". Seçim kullanıcının eylemidir;
    /// okuma ve boyut kararı `AIFileAttachmentLoader`'ın, maskeleme her zamanki sınırın.
    ///
    /// Bir dosya eklenemezse diğerleri YİNE eklenir: tek bozuk dosya yüzünden seçimin
    /// tamamını atmak, kullanıcıyı hangisinin sorunlu olduğunu aramaya bırakırdı.
    func attachFiles() {
        var failures: [String] = []
        for url in chooseFiles() {
            switch AIFileAttachmentLoader.load(contentsOf: url, reading: readFile) {
            case let .success(file):
                // Aynı dosya iki kez eklenmez: bağlamı sessizce ikiye katlardı.
                if !attachments.contains(where: { $0.name == file.name && $0.text == file.text }) {
                    attachments.append(file)
                }
            case let .failure(reason):
                failures.append(reason.message)
            }
        }
        attachmentFailure = failures.isEmpty ? nil : failures.joined(separator: "\n")
        refreshContext()
    }

    func removeAttachment(_ file: AIFileAttachment) {
        attachments.removeAll { $0.id == file.id }
        refreshContext()
    }

    func removeAllAttachments() {
        attachments.removeAll()
        attachmentFailure = nil
        refreshContext()
    }

    func refreshContext() {
        var snapshot = bridge?.captureContext() ?? AIContextSnapshot()
        // Eklenen dosyalar terminalden GELMEZ, panelde durur; bağlam sınırına burada
        // katılır ki maskeleme ve boyut kuralı onlara da uygulansın.
        snapshot[.attachedFiles] = AIFileAttachment.combinedText(of: attachments)
        preparedContext = AIContextBuilder.prepare(snapshot,
                                                   preferences: settings.settings.aiContext)
    }

    /// Göstergedeki tek satır: kaç parça gidiyor ve ne saklandı.
    var contextSummary: String {
        guard !preparedContext.isEmpty else { return Self.emptyContextSummary }
        let items = Pluralize.count(preparedContext.entries.count, "item")
        guard preparedContext.didFindSecrets else { return "\(items) will be sent." }
        return "\(items) will be sent · \(preparedContext.maskingSummary)"
    }

    // MARK: - Gönderim

    var canSend: Bool { sendDisabledReason == nil }

    /// Gönderimin neden kapalı olduğu. Devre dışı bir düğmenin sebebi görünmezse
    /// kullanıcı ne yapacağını bilemez.
    var sendDisabledReason: String? {
        if sendState == .sending { return "Waiting for the model's answer." }
        if selectedModel == nil { return "Choose a model first." }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Type a question first."
        }
        return nil
    }

    func send() async {
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !question.isEmpty else { return }
        // Alan İSTEK BAŞARILI OLUNCA temizlenir; hata hâlinde kullanıcının yazdığı durur.
        await ask(question, clearingPrompt: true)
    }

    /// briefs/3 "AI Paneli": Explain eylemi. Kullanıcı hiçbir şey yazmadan bir komutun
    /// ne yaptığını sorabilir.
    func explain(_ suggestion: AICommandSuggestion) async {
        await ask("""
            Explain what this command does, step by step, and say when it would be unsafe:

            ```
            \(suggestion.command)
            ```
            """, clearingPrompt: false)
    }

    /// Seçili çıktı var mı — Explain Selection düğmesi buna göre etkinleşir.
    var canExplainSelection: Bool {
        preparedContext.entries.contains { $0.kind == .selectedOutput || $0.kind == .selectedCommand }
    }

    /// briefs/2 "Hata Açıklama": başarısız bir komut seçildiğinde olası neden, ilgili
    /// satırlar ve GÜVENLİ çözüm adımları istenir.
    ///
    /// Kullanıcı terminalde metni seçer, bağlam oradan gelir. Bloktan gelen istek için
    /// `explainCommandBlock(_:)`.
    func explainSelection() async {
        guard canExplainSelection else { return }
        await ask("""
            The selected command failed. Using the terminal context above, tell me:
            the most likely cause, which output lines show it, and safe steps to fix it.
            If a command would fix it, show it in a code block and say what it changes.
            """, clearingPrompt: false)
    }

    /// briefs/2 "Komut Blokları" ▸ *Hata çıktısını AI ile açıklayabilmeli.*
    ///
    /// Blok metni soruya GÖMÜLÜR, terminal seçimi olarak değil: seçim yolu kullanıcının o
    /// an ekranda işaretlediği metni okur ve blok paneli açıkken kullanıcı hiçbir şey
    /// seçmemiş olabilir.
    ///
    /// Metin, isteği kuran ortak yoldan geçtiği için maskelemeye tabidir (briefs/2 "Secret
    /// Maskeleme") — blok çıktısında duran bir token dışarı çıkmaz.
    func explainCommandBlock(_ block: CommandBlock) async {
        let question = """
            Explain this command and its result. Tell me what it did, whether it succeeded, \
            and — if it failed — the most likely cause and safe steps to fix it. If a command \
            would fix it, show it in a code block and say what it changes.

            \(CommandBlockMarkdown.text(for: block))
            """
        await ask(question, clearingPrompt: false)
    }

    /// Tek soru-cevap turu. Bağlam gönderim ANINDA tazelenir: kullanıcı yazarken
    /// terminalde `cd` yapmış olabilir.
    private func ask(_ question: String, clearingPrompt: Bool) async {
        guard let model = selectedModel, sendState != .sending else { return }
        refreshContext()

        let request = AIRequestBuilder.build(model: model,
                                             prompt: question,
                                             context: preparedContext,
                                             history: conversation.history)
        sendState = .sending
        streamingText = ""
        do {
            var answer = ""
            for try await delta in provider.stream(request) {
                answer += delta
                streamingText = answer
                onStreamDelta?()
            }
            let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw AIProviderError.malformedResponse("the model returned an empty answer")
            }
            // Konuşmaya YALNIZ burada, akış BİTİNCE yazılır. Komut önerileri mesaj
            // metninden çıkarılıyor; yarım bir kod bloğu çalıştırılabilir görünen ama
            // eksik bir komut üretir ve Run düğmesi onu onaylatırdı.
            streamingText = nil
            conversation.append(AIMessage(role: .user, text: question))
            conversation.append(AIMessage(role: .assistant, text: text))
            if clearingPrompt { prompt = "" }
            sendState = .idle
        } catch let error as AIProviderError {
            // Yarım gelen metin EKRANDA BIRAKILMAZ: tam sanmak en kötü sonuç olurdu.
            streamingText = nil
            sendState = .failed(error)
        } catch {
            streamingText = nil
            sendState = .failed(.malformedResponse(error.localizedDescription))
        }
    }

    func newConversation() {
        conversation = AIConversation()
        sendState = .idle
        prompt = ""
    }

    // MARK: - Komut eylemleri

    func copy(_ suggestion: AICommandSuggestion) {
        copyToClipboard(suggestion.command)
    }

    /// Komutu terminale YAZAR ama çalıştırmaz; kullanıcı düzenleyip kendisi return'e basar
    /// (briefs/2: "Terminal girişine ekleyebilir", "Düzenleyebilir").
    func insert(_ suggestion: AICommandSuggestion) {
        bridge?.insert(suggestion.terminalText)
    }

    /// Onay penceresini AÇAR. Terminale dokunmaz — briefs/2'nin kırmızı çizgisi budur.
    func requestRun(_ suggestion: AICommandSuggestion) {
        pendingRun = suggestion
    }

    /// Onaylanan komutu çalıştırır. Bekleyen komut yoksa hiçbir şey olmaz, böylece
    /// kapanmış bir onay penceresi ikinci kez komut çalıştıramaz.
    func confirmRun() {
        guard let suggestion = pendingRun else { return }
        pendingRun = nil
        bridge?.run(suggestion.terminalText)
    }

    func cancelRun() {
        pendingRun = nil
    }
}
