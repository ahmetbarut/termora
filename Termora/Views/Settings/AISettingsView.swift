import SwiftUI

// MARK: - İçerik (saf metin, test edilebilir)

/// Ayarlar ▸ AI sayfasının açıklama metinleri.
///
/// Metin `body` içinde kurulmaz: bir gizlilik vaadi (–"geçmişin tamamı gönderilmez"–)
/// arayüz kodunun içinde yaşarsa test edilemez ve sessizce değişebilir.
enum AISettingsContent {

    static let providerFooter = "Ollama runs on this Mac and asks for no API key, so Termora "
        + "stores no credentials for it."

    static let endpointHelp = "The address Termora sends questions to. The default is Ollama's own."

    static let modelHelp = "Termora lists the models already downloaded on this Mac; it never "
        + "downloads one for you."

    static let contextFooter = "Termora sends only the items you leave on here. Your whole terminal "
        + "history is never sent, and there is no switch to turn that on."

    static let maskingNote = "Whatever is sent goes through secret masking first, and the panel "
        + "shows you the exact text before you send it."

    static let allProse = [providerFooter, endpointHelp, modelHelp, contextFooter, maskingNote]

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

    var body: some View {
        Form {
            Section {
                LabeledContent("Provider") {
                    Text(catalog.providerName)
                        .foregroundStyle(.secondary)
                }

                TextField("Endpoint", text: $endpointDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitEndpoint)
                    .accessibilityLabel("Ollama server address")
                    .accessibilityHint(AISettingsContent.endpointHelp)

                HStack {
                    Text(AISettingsContent.endpointHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Default") {
                        endpointDraft = OllamaEndpoint.defaultAddress
                        commitEndpoint()
                    }
                    .disabled(endpointDraft == OllamaEndpoint.defaultAddress)
                }
            } header: {
                Text("Provider")
            } footer: {
                Text(AISettingsContent.providerFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .onAppear {
            endpointDraft = settings.settings.aiEndpoint
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
        let normalized = OllamaEndpoint.url(from: endpointDraft)?.absoluteString
        settings.settings.aiEndpoint = normalized ?? endpointDraft
        endpointDraft = settings.settings.aiEndpoint
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
