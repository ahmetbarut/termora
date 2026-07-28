import SwiftUI

/// briefs/3 "AI Paneli". Sağdan açılır, 360–420 pt.
///
/// Panel terminalin ÜZERİNE binmez, YANINDA durur (bkz. `MainWindowView`): oturumlar
/// okumaya ve çalışmaya devam eder, klavye odağı panele girmedikçe terminaldedir.
///
/// Bölümler brief'in sırasıyla: konuşma başlığı, mesaj geçmişi, gönderilecek bağlam
/// göstergesi, prompt giriş alanı, sağlayıcı ve model seçimi.
struct AIPanelView: View {

    @Bindable var model: AIPanelModel

    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messages
            Divider()
            contextIndicator
            Divider()
            composer
            Divider()
            providerBar
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .task {
            // Panel AÇILDIĞINDA sorulur; kapalıyken hiçbir ağ isteği olmaz.
            if model.availability == .idle { await model.refreshModels() }
            model.refreshContext()
        }
        // "Ask the AI Assistant" (palet / menü) yalnız bir jeton bırakır; odağı kuran yer
        // burasıdır. Bir sonraki tura ERTELENİR: @FocusState'i eklendiği güncelleme
        // turunda atamak güvenilir değil (aynı tuzak palet ve arama çubuğunda yaşandı).
        .onChange(of: model.promptFocusRequest) { _, request in
            guard request != nil else { return }
            DispatchQueue.main.async { isPromptFocused = true }
        }
        .confirmationDialog(
            AIRunPrompt.title,
            isPresented: pendingRunBinding,
            titleVisibility: .visible
        ) {
            // Belirsiz "OK"/"Yes" yerine eylemin adı (briefs/3 "Uygulama Metin Dili").
            Button(AIRunPrompt.confirmTitle, role: model.pendingRun?.isRisky == true ? .destructive : nil) {
                model.confirmRun()
            }
            Button(AIRunPrompt.cancelTitle, role: .cancel) { model.cancelRun() }
        } message: {
            // Sayfanın verdiği öğe kullanılır; dışarıdaki state yeniden OKUNMAZ.
            Text(model.pendingRun.map { AIRunPrompt.message(for: $0.command) } ?? "")
        }
    }

    // MARK: - 1. Konuşma başlığı

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(DesignTokens.accentViolet.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.providerName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                model.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .disabled(model.conversation.messages.isEmpty)
            .help("Start a new conversation")
            .accessibilityLabel("Start a new conversation")

            Button {
                model.isPresented = false
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.borderless)
            .help("Hide the AI panel")
            .accessibilityLabel("Hide the AI panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 2. Mesaj geçmişi

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let status = model.status {
                        AIStatusView(status: status)
                    }
                    if model.conversation.messages.isEmpty, model.status == nil {
                        emptyState
                    }
                    ForEach(model.conversation.messages) { message in
                        AIMessageView(message: message, model: model)
                            .id(message.id)
                    }
                    if model.sendState == .sending {
                        Label("Waiting for \(model.selectedModel ?? "the model")…",
                              systemImage: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .onChange(of: model.conversation.messages.count) { _, _ in
                guard let last = model.conversation.messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// briefs/3 "Empty State": tek cümle + birincil eylem. İllüstrasyon yok.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask for a shell command or an explanation.")
                .font(.callout)
            Text("Termora shows the command; nothing runs until you confirm it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.canExplainSelection {
                Button("Explain Selection") {
                    Task { await model.explainSelection() }
                }
                .accessibilityHint("Asks why the selected command failed and how to fix it safely")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 3. Gönderilecek bağlam göstergesi

    /// briefs/2: "Kullanıcı gönderilecek son içeriği AI isteğinden önce inceleyebilmelidir."
    private var contextIndicator: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.isContextExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.isContextExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Image(systemName: "doc.text.magnifyingglass")
                        .accessibilityHidden(true)
                    Text(model.contextSummary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Context to be sent. \(model.contextSummary)")
            .accessibilityHint("Shows the exact text Termora will send")

            attachmentBar

            if model.isContextExpanded {
                if model.preparedContext.isEmpty {
                    Text(AIPanelModel.emptyContextSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.preparedContext.entries) { entry in
                        contextRow(entry)
                    }
                }
                Text("Change what is sent in Settings ▸ AI.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .motionAnimation(.panel, value: model.isContextExpanded)
    }

    /// briefs/2 "Kullanıcının açıkça eklediği dosyalar". Eklenen her dosya adıyla görünür
    /// ve tek tıkla kaldırılabilir; ne gönderildiği hiçbir an belirsiz kalmaz.
    @ViewBuilder
    private var attachmentBar: some View {
        HStack(spacing: 6) {
            Button {
                model.attachFiles()
            } label: {
                Label("Attach Files", systemImage: "paperclip")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach files to send with your question")

            if !model.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.attachments) { file in
                            attachmentChip(file)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }

        if let failure = model.attachmentFailure {
            // Eklenemeyen dosya SESSİZ kalmaz: kullanıcı gönderdiğini sanabilirdi.
            Text(failure)
                .font(.caption2)
                .foregroundStyle(DesignTokens.warning.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func attachmentChip(_ file: AIFileAttachment) -> some View {
        HStack(spacing: 3) {
            Text(file.name)
                .font(.caption2)
                .lineLimit(1)
            Button {
                model.removeAttachment(file)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(file.name) from the context")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
    }

    private func contextRow(_ entry: AIContextEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.kind.symbolName)
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(entry.kind.title)
                    .font(.caption.weight(.semibold))
                if entry.didFindSecrets {
                    // Maskeleme yalnız renkle değil, SÖZLE anlatılır.
                    Text("secret hidden")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DesignTokens.warning.color.opacity(0.20))
                        )
                }
            }
            Text(entry.value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.kind.title): \(entry.value)")
    }

    // MARK: - 4. Prompt giriş alanı

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Ask about this terminal…", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isPromptFocused)
                .onSubmit(send)
                .accessibilityLabel("Question for the assistant")

            HStack(spacing: 8) {
                if model.canExplainSelection {
                    Button("Explain Selection") {
                        Task { await model.explainSelection() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                Spacer(minLength: 0)
                // Devre dışı düğmenin SEBEBİ görünür: kullanıcı ne yapacağını bilmeli.
                if let reason = model.sendDisabledReason, !model.prompt.isEmpty || model.selectedModel == nil {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Send", action: send)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSend)
                    .accessibilityLabel("Send question to the model")
                    .accessibilityHint(model.sendDisabledReason ?? "")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func send() {
        Task { await model.send() }
    }

    // MARK: - 5. Sağlayıcı ve model seçimi

    private var providerBar: some View {
        HStack(spacing: 8) {
            if model.installedModels.isEmpty {
                // Boş açılır liste YOK: ne olduğunu söyleyen bir satır ve tazeleme düğmesi.
                Text(AISettingsContent.noModelPlaceholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: modelBinding) {
                    ForEach(model.installedModels) { installed in
                        Text(installed.displayName).tag(Optional(installed.name))
                    }
                }
                .labelsHidden()
                .font(.caption)
                .accessibilityLabel("Model")
            }

            Spacer(minLength: 0)

            Button {
                Task { await model.refreshModels() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
            .help("Refresh the list of installed models")
            .accessibilityLabel("Refresh the list of installed models")

            Text(model.endpointDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var modelBinding: Binding<String?> {
        Binding(get: { model.selectedModel }, set: { model.selectedModel = $0 })
    }

    private var pendingRunBinding: Binding<Bool> {
        Binding(
            get: { model.pendingRun != nil },
            set: { isPresented in if !isPresented { model.cancelRun() } }
        )
    }
}

// MARK: - Tek mesaj

/// Bir mesaj balonu. Asistan cevabı düz metin ve komut bloklarına ayrılır; komut
/// bloklarının altında briefs/3'ün dört eylemi durur.
struct AIMessageView: View {
    let message: AIMessage
    let model: AIPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(roleTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if message.role == .assistant {
                ForEach(AIReplyParser.segments(in: message.text)) { segment in
                    switch segment {
                    case let .prose(_, text):
                        Text(text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    case let .command(suggestion):
                        AICommandBlockView(suggestion: suggestion, model: model)
                    }
                }
            } else {
                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roleTitle: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Assistant"
        case .system: "Termora"
        }
    }
}

// MARK: - Komut bloğu

/// Üretilen bir komut + Copy · Insert · Explain · Run (briefs/3).
///
/// Riskli komutta kırmızı uyarı alanı gösterilir; renk TEK gösterge değildir — alanda
/// simge, seviyeyi adlandıran etiket ve sonucu anlatan cümle vardır, VoiceOver da
/// aynı cümleyi okur.
struct AICommandBlockView: View {
    let suggestion: AICommandSuggestion
    let model: AIPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                )
                .accessibilityLabel("Suggested command: \(suggestion.command)")

            if let explanation = suggestion.riskExplanation,
               let label = suggestion.riskLabel,
               let symbol = suggestion.riskSymbolName {
                riskArea(symbol: symbol, label: label, explanation: explanation)
            }

            HStack(spacing: 6) {
                ForEach(AICommandAction.allCases) { action in
                    Button {
                        perform(action)
                    } label: {
                        Label(action.title, systemImage: action.symbolName)
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(action.accessibilityLabel)
                }
            }
        }
    }

    private func riskArea(symbol: String, label: String, explanation: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(DesignTokens.danger.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                Text(explanation)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Run asks for confirmation first.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DesignTokens.danger.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(DesignTokens.danger.color.opacity(0.45))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(suggestion.riskAccessibilityLabel ?? label)
    }

    private func perform(_ action: AICommandAction) {
        switch action {
        case .copy: model.copy(suggestion)
        case .insert: model.insert(suggestion)
        case .explain: Task { await model.explain(suggestion) }
        case .run: model.requestRun(suggestion)
        }
    }
}
