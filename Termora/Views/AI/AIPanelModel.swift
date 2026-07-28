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
    /// Onay bekleyen komut. Doluyken terminale HİÇBİR ŞEY yazılmamıştır.
    private(set) var pendingRun: AICommandSuggestion?

    init(provider: any AIProviding, settings: SettingsStore) {
        self.provider = provider
        self.settings = settings
        self.catalog = AIModelCatalog(provider: provider, settings: settings)
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

    // MARK: - Bağlam

    /// Terminalden bağlamı okur, tercihlerden geçirir ve MASKELER.
    /// Panel açılırken, aktif panel değişince ve gönderim öncesi çağrılır.
    func refreshContext() {
        let snapshot = bridge?.captureContext() ?? AIContextSnapshot()
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
    /// Komut blokları henüz yok; kullanıcı terminalde metni seçer, bağlam oradan gelir.
    func explainSelection() async {
        guard canExplainSelection else { return }
        await ask("""
            The selected command failed. Using the terminal context above, tell me:
            the most likely cause, which output lines show it, and safe steps to fix it.
            If a command would fix it, show it in a code block and say what it changes.
            """, clearingPrompt: false)
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
        do {
            let reply = try await provider.complete(request)
            conversation.append(AIMessage(role: .user, text: question))
            conversation.append(AIMessage(role: .assistant, text: reply.text))
            if clearingPrompt { prompt = "" }
            sendState = .idle
        } catch let error as AIProviderError {
            sendState = .failed(error)
        } catch {
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
        bridge?.insert(suggestion.command)
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
        bridge?.run(suggestion.command)
    }

    func cancelRun() {
        pendingRun = nil
    }
}
