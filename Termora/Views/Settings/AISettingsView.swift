import SwiftUI

// MARK: - İçerik (saf metin, test edilebilir)

/// Ayarlar ▸ AI sayfasının açıklama metinleri.
///
/// Metin `body` içinde kurulmaz: bir gizlilik vaadi (–"geçmişin tamamı gönderilmez"–)
/// arayüz kodunun içinde yaşarsa test edilemez ve sessizce değişebilir.
enum AISettingsContent {

    static let providerFooter = "Ollama runs on this Mac and asks for no API key, so Termora "
        + "stores no credentials for it."

    /// briefs/1 "Güvenlik": anahtar Keychain'de tutulur. Kullanıcı bunu görebilmeli —
    /// bir gizlilik vaadi ancak söylendiğinde vaattir.
    static let apiKeyFooter = "The key is stored in your macOS Keychain, never in Termora's "
        + "settings file. Clearing the field removes it from the Keychain."

    static let endpointHelp = "The address Termora sends questions to. The default is Ollama's own."

    static let modelHelp = "Termora lists the models already downloaded on this Mac; it never "
        + "downloads one for you."

    static let contextFooter = "Termora sends only the items you leave on here. Your whole terminal "
        + "history is never sent, and there is no switch to turn that on."

    static let maskingNote = "Whatever is sent goes through secret masking first, and the panel "
        + "shows you the exact text before you send it."

    static let allProse = [providerFooter, apiKeyFooter, endpointHelp, modelHelp,
                           contextFooter, maskingNote]

    /// Model listesi boşken/başarısızken açılır listenin yerine geçen tek satır.
    static let noModelPlaceholder = "No model available"
}

// MARK: - Görünüm

/// briefs/2 "Ayarlar Ekranı" ▸ AI: uç nokta, model seçimi, bağlam tercihleri.
struct AISettingsView: View {

    let catalog: AIModelCatalog
    let settings: SettingsStore

    /// Adres alanı yazarken her tuşta ayara YAZILMAZ: yarım yazılmış bir adres
    /// (`http://localh`) kaydedilir ve panel o adrese istek atmaya çalışırdı.
    @State private var endpointDraft = ""
    @State private var isRefreshing = false

    /// Anahtar taslağı. Ayara YAZILMAZ — `commitAPIKey` onu Keychain'e koyar.
    @State private var apiKeyDraft = ""
    @State private var keychainFailure: String?

    private let keychain = KeychainService()

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: providerBinding) {
                    ForEach(AIProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                TextField("Endpoint", text: $endpointDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitEndpoint)
                    .accessibilityLabel("\(selectedProvider.displayName) server address")
                    .accessibilityHint(AISettingsContent.endpointHelp)

                HStack {
                    Text(AISettingsContent.endpointHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let fallback = selectedProvider.defaultEndpoint {
                        Button("Use Default") {
                            endpointDraft = fallback
                            commitEndpoint()
                        }
                        .disabled(endpointDraft == fallback)
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                // Yerel sağlayıcının gizlilik vaadi yalnız ONUN için doğrudur; uzak
                // sağlayıcı seçiliyken göstermek yanlış güven verirdi.
                if selectedProvider == .ollama {
                    Text(AISettingsContent.providerFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Anahtar alanı yalnız anahtar İSTEYEN sağlayıcıda çizilir: Ollama'ya alan
            // göstermek, olmayan bir sırrı varmış gibi göstermek olurdu.
            if selectedProvider.requiresAPIKey {
                Section {
                    SecureField("API key", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitAPIKey)
                        .accessibilityLabel("\(selectedProvider.displayName) API key")
                        .accessibilityHint(AISettingsContent.apiKeyFooter)

                    if let failure = keychainFailure {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text(AISettingsContent.apiKeyFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                modelRow
                if let status = catalog.status {
                    AIStatusView(status: status)
                }
            } header: {
                Text("Model")
            } footer: {
                Text(AISettingsContent.modelHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(AIContextKind.allCases) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                            Text(kind.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityLabel("Send \(kind.title.lowercased())")
                    .accessibilityHint(kind.purpose)
                }
            } header: {
                Text("Context")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AISettingsContent.contextFooter)
                    Text(AISettingsContent.maskingNote)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDraftsForSelectedProvider)
        .task {
            // Sayfa açıldığında liste bir kez sorulur; yoksa kullanıcı gerekçesiz bir
            // "No model available" satırına bakar ve ne yapacağını bilemez.
            if catalog.availability == .idle { await catalog.refresh() }
        }
    }

    @ViewBuilder
    private var modelRow: some View {
        HStack {
            if catalog.installedModels.isEmpty {
                // Boş bir açılır liste kullanıcıya hiçbir şey anlatmaz; yerine tek satır
                // metin durur ve altındaki durum alanı ne yapılacağını söyler.
                LabeledContent("Model") {
                    Text(AISettingsContent.noModelPlaceholder)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Model", selection: modelBinding) {
                    ForEach(catalog.installedModels) { model in
                        Text(label(for: model)).tag(Optional(model.name))
                    }
                }
            }
            Spacer()
            Button {
                Task {
                    isRefreshing = true
                    await catalog.refresh()
                    isRefreshing = false
                }
            } label: {
                Text(isRefreshing ? "Checking…" : "Refresh")
            }
            .disabled(isRefreshing)
            .accessibilityLabel("Refresh the list of installed models")
        }
    }

    private func label(for model: AIModel) -> String {
        guard let size = model.sizeDescription else { return model.displayName }
        return "\(model.displayName) — \(size)"
    }

    private var modelBinding: Binding<String?> {
        Binding(get: { catalog.selectedModel }, set: { catalog.selectedModel = $0 })
    }

    private func binding(for kind: AIContextKind) -> Binding<Bool> {
        Binding(
            get: { settings.settings.aiContext.includes(kind) },
            set: { settings.settings.aiContext.setIncludes(kind, $0) }
        )
    }

    /// Adres ayara YAZILIRKEN normalleştirilir; kullanıcı `localhost:11434` yazdıysa
    /// kaydedilen `http://localhost:11434` olur ve panel ile ayar aynı şeyi gösterir.
    private func commitEndpoint() {
        let normalized = RemoteEndpoint.url(from: endpointDraft)?.absoluteString
        settings.settings.aiEndpoint(for: selectedProvider, is: normalized ?? endpointDraft)
        endpointDraft = settings.settings.aiEndpoint(for: selectedProvider)
    }

    // MARK: - Sağlayıcı seçimi

    private var selectedProvider: AIProviderKind { settings.settings.aiProviderKind }

    private var providerBinding: Binding<AIProviderKind> {
        Binding(
            get: { selectedProvider },
            set: { newValue in
                // Yazılmakta olan taslak önce kaydedilir: sağlayıcı değiştirmek,
                // kullanıcının henüz Enter'lamadığı adresi çöpe atmamalı.
                commitEndpoint()
                settings.settings.aiProviderKind = newValue
                loadDraftsForSelectedProvider()
                // Model listesi sağlayıcıya özgüdür; eskisini göstermek yanlış olurdu.
                Task { await catalog.refresh() }
            }
        )
    }

    private func loadDraftsForSelectedProvider() {
        endpointDraft = settings.settings.aiEndpoint(for: selectedProvider)
        // Anahtar Keychain'den okunur; ayar dosyasında hiç bulunmaz.
        apiKeyDraft = (try? keychain.secret(account: selectedProvider.keychainAccount ?? "")) ?? ""
        keychainFailure = nil
    }

    /// Boş alan anahtarı SİLER (bkz. `KeychainService.setSecret`): kullanıcı alanı
    /// temizlediğinde anahtarın Keychain'de kalması, sildiğini sanmasına yol açardı.
    private func commitAPIKey() {
        guard let account = selectedProvider.keychainAccount else { return }
        do {
            try keychain.setSecret(apiKeyDraft, account: account)
            keychainFailure = nil
        } catch {
            // Sessizce yutmak, kullanıcının kaydettiğini sanıp isteklerin 401 almasına
            // yol açardı (briefs/3 "Error State").
            keychainFailure = "Termora could not write to the Keychain: \(error)"
        }
    }
}

// MARK: - Durum alanı

/// briefs/3 "Error State": ne başarısız oldu, muhtemel sebep, kullanıcı ne yapabilir,
/// teknik detay nasıl görüntülenir.
///
/// Renk TEK gösterge değildir: başlıkta simge, gövdede cümleler ve VoiceOver etiketi var.
struct AIStatusView: View {
    let status: AIPanelStatus

    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(status.title, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DesignTokens.warning.color)

            Text(status.reason)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text(status.recovery)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $showsDetail) {
                Text(status.technicalDetail)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text("Technical detail")
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DesignTokens.warning.color.opacity(0.10))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status.title). \(status.reason) \(status.recovery)")
    }
}
