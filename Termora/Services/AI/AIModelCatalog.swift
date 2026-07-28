import Foundation
import Observation

/// Kurulu modellerin listesi ve seçili model.
///
/// Ayrı bir tip: aynı bilgiye İKİ ekran bakıyor (AI paneli ve Ayarlar ▸ AI) ve ikisinin
/// de "model yok" durumunu aynı cümlelerle anlatması gerekiyor. Mantık panelde kalsaydı
/// Ayarlar ekranı onu kopyalardı ve iki ekran zamanla ayrışırdı.
@MainActor
@Observable
final class AIModelCatalog {

    /// Nesne grafiğinin kökü `AppServices`'tir; Ayarlar penceresini kuran `TermoraApp` ise
    /// bu görevin kapsamı dışında, yani katalog oraya argüman olarak GEÇİRİLEMİYOR.
    /// `AppServices` kurulurken kendi kataloğunu buraya yazar ve Ayarlar ▸ AI onu bulur —
    /// böylece iki ekran AYNI `SettingsStore`'u paylaşır (ikinci bir depo kurulsaydı
    /// Ayarlar'da değiştirilen adresi panel hiç görmezdi).
    @ObservationIgnored
    static var current: AIModelCatalog?

    private let provider: any AIProviding
    private let settings: SettingsStore

    private(set) var availability: AIModelAvailability = .idle

    init(provider: any AIProviding, settings: SettingsStore) {
        self.provider = provider
        self.settings = settings
    }

    /// Kullanıcının seçtiği model. Depo `AppSettings`'tir: seçim Ayarlar ve panel
    /// arasında paylaşılır ve uygulama yeniden açıldığında korunur.
    var selectedModel: String? {
        get { settings.settings.aiModel }
        set { settings.settings.aiModel = newValue }
    }

    var installedModels: [AIModel] {
        if case let .ready(models) = availability { return models }
        return []
    }

    var isLoading: Bool { availability == .loading }

    /// Liste alınamadıysa gösterilecek dört soruluk durum; sorun yoksa nil.
    var status: AIPanelStatus? {
        if case let .unavailable(error) = availability { return AIPanelStatus(error) }
        return nil
    }

    var providerName: String { provider.kind.displayName }

    var endpointDescription: String { provider.endpointDescription }

    /// Kurulu modelleri sorar.
    ///
    /// Her yol bir SONUÇ durumuna varır (`ready` ya da `unavailable`); `loading` durumunda
    /// kalınamaz, bu yüzden panelde sonsuz spinner oluşamaz (briefs/3 "Loading State").
    func refresh() async {
        availability = .loading
        do {
            let models = try await provider.availableModels()
            availability = .ready(models)
            reconcileSelection(with: models)
        } catch let error as AIProviderError {
            availability = .unavailable(error)
        } catch {
            // Beklenmedik bir hata da yutulmaz (briefs/2 "Hatalar sessizce yutulmamalı").
            availability = .unavailable(.malformedResponse(error.localizedDescription))
        }
    }

    /// Seçili model artık kurulu değilse kurulu olana düşer.
    ///
    /// Sessizce korunsaydı ilk istek 404 ile patlar ve kullanıcı sebebini göremezdi;
    /// Termora ise bir model adı UYDURMAZ, listeden seçer.
    private func reconcileSelection(with models: [AIModel]) {
        guard let first = models.first else {
            selectedModel = nil
            return
        }
        if let selected = selectedModel, models.contains(where: { $0.name == selected }) { return }
        selectedModel = first.name
    }
}
