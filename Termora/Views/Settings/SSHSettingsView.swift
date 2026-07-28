import AppKit
import SwiftUI

// MARK: - Satır metni

/// "Son bağlantı zamanı" metni (briefs/3 SSH listesi).
///
/// `WorkspaceRelativeTime` ile aynı basamaklar; sözcükler bağlantıya aittir.
/// Damga bağlantının BAŞLATILDIĞI andır: ssh süreci terminal panelinin içinde çalışır,
/// oturumun ne zaman bittiğini uygulama göremez.
enum SSHRelativeTime {

    static let neverText = "Never connected"

    private static let minute: Double = 60
    private static let hour: Double = 60 * 60
    private static let day: Double = 24 * 60 * 60
    private static let week: Double = 7 * 24 * 60 * 60
    private static let month: Double = 30 * 24 * 60 * 60
    private static let year: Double = 365 * 24 * 60 * 60

    static func text(lastConnectedAt: Date?, now: Date) -> String {
        guard let lastConnectedAt else { return neverText }
        // Saat geri alınmışsa gelecek bir damga oluşur; negatif süre yazmak yerine
        // en yakın anlamlı ifadeye düşülür.
        let elapsed = max(0, now.timeIntervalSince(lastConnectedAt))

        switch elapsed {
        case ..<minute: return "Connected just now"
        case ..<hour: return connected(Int(elapsed / minute), "minute")
        case ..<day: return connected(Int(elapsed / hour), "hour")
        case ..<week: return connected(Int(elapsed / day), "day")
        case ..<month: return connected(Int(elapsed / week), "week")
        case ..<year: return connected(Int(elapsed / month), "month")
        default: return connected(Int(elapsed / year), "year")
        }
    }

    private static func connected(_ count: Int, _ unit: String) -> String {
        "Connected \(Pluralize.count(count, unit)) ago"
    }
}

/// briefs/3 "SSH Ekranı" satırının TÜM metni.
///
/// Brief satırda bir DURUM sütunu da ister (Disconnected / Connecting / Connected /
/// Failed). Bu sürümde durum GÖSTERİLMEZ: `ssh`, kullanıcının kabuğunun içinde, bir
/// terminal panelinde çalışır ve o süreci izleyen bir yüzey henüz yok. Uydurma bir
/// "Connected" rozeti kullanıcıyı yanıltırdı; bu yüzden yalnız gerçekten bilinen şey
/// gösterilir: bağlantının en son ne zaman BAŞLATILDIĞI.
struct SSHHostRowModel: Equatable, Identifiable {

    /// Adsız kayıt listede ve VoiceOver'da sessiz kalmaz.
    static let untitledName = "Untitled SSH Host"
    static let savedSourceText = "Saved"
    static let configSourceText = "~/.ssh/config"

    let id: String
    let name: String
    /// "deploy@pinro.app:2222".
    let destinationText: String
    /// "deploy"; kullanıcı belirtilmemişse nil.
    let userText: String?
    let tags: [String]
    let sourceText: String
    let lastConnectedText: String
    /// Renk noktasının hex'i; renk TEK sinyal değildir, satır metni de her şeyi söyler.
    let colorHex: String?
    /// Kayıtlı profil mi? (config hostları düzenlenip silinemez.)
    let isEditable: Bool
    let accessibilityLabel: String
    let connectAccessibilityLabel: String
    let copyAccessibilityLabel: String
    let editAccessibilityLabel: String
    let deleteAccessibilityLabel: String

    static func make(target: SSHTarget, now: Date) -> SSHHostRowModel {
        let name = displayName(target.displayName)
        let isEditable: Bool
        let colorHex: String?
        switch target {
        case let .profile(host):
            isEditable = true
            colorHex = host.colorHex
        case .configHost:
            isEditable = false
            colorHex = nil
        }
        let sourceText = isEditable ? savedSourceText : configSourceText
        let lastConnectedText = SSHRelativeTime.text(lastConnectedAt: target.lastConnectedAt, now: now)

        var spoken: [String] = [name, target.destinationText]
        if let user = target.userText { spoken.append("user \(user)") }
        if !target.tags.isEmpty { spoken.append("tags \(target.tags.joined(separator: ", "))") }
        spoken.append(sourceText == configSourceText ? "from ssh config" : "saved host")
        spoken.append(lastConnectedText)

        return SSHHostRowModel(
            id: target.id,
            name: name,
            destinationText: target.destinationText,
            userText: target.userText,
            tags: target.tags,
            sourceText: sourceText,
            lastConnectedText: lastConnectedText,
            colorHex: colorHex,
            isEditable: isEditable,
            accessibilityLabel: spoken.joined(separator: ", "),
            connectAccessibilityLabel: "Connect to \(name)",
            copyAccessibilityLabel: "Copy ssh command for \(name)",
            editAccessibilityLabel: "Edit SSH host \(name)",
            deleteAccessibilityLabel: "Delete SSH host \(name)")
    }

    static func displayName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitledName : trimmed
    }
}

/// briefs/3 "Empty State": tek cümlelik açıklama + birincil eylem.
enum SSHEmptyState {
    static let title = "No SSH hosts yet"
    static let message = "Termora connects with the system ssh client and your ~/.ssh/config; it never stores your keys or passwords."
    static let primaryActionTitle = "New SSH Host"
}

// MARK: - Düzenleme taslağı

/// SSH profili formunun durumu. Metin alanları String tutar; kaydederken boş alanlar
/// `nil`'e çevrilir ki üretilen komuta boş argüman sızmasın.
struct SSHHostDraft: Equatable, Identifiable {
    var hostID: UUID?
    var name: String = ""
    var hostName: String = ""
    var port: String = ""
    var user: String = ""
    var authenticationMethod: SSHAuthenticationMethod = .automatic
    var identityFile: String = ""
    var startupDirectory: String = ""
    var startupCommand: String = ""
    var tags: String = ""
    var colorHex: String = ""
    var proxyJump: String = ""
    /// Düzenlenen kaydın damgası korunur; form onu değiştirmez.
    var lastConnectedAt: Date?

    var id: String { hostID?.uuidString ?? "new" }

    var isEditingExistingHost: Bool { hostID != nil }

    /// Host olmadan bağlanılacak bir yer yoktur; ad boşsa host adı kullanılır.
    var isSaveEnabled: Bool {
        !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Girilen port sayı değilse ya da aralık dışındaysa uyarı gösterilir; kayıtta
    /// alan boş bırakılır (yanlış bir port sessizce KAYDEDİLMEZ).
    var portWarning: String? {
        let trimmed = port.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), SSHCommand.isUsablePort(value) else {
            return "Port must be a number between 1 and 65535. It will be left unset."
        }
        return nil
    }

    static let commandPreviewPlaceholder = "Enter a host to preview the ssh command."

    /// Kaydetmeden ÖNCE ne çalışacağı. Kullanıcı alanlarının komuta nasıl döndüğünü —
    /// ve hiçbir doğrulama seçeneğinin eklenmediğini — burada gözle görür.
    var commandPreviewText: String {
        guard isSaveEnabled else { return Self.commandPreviewPlaceholder }
        return SSHCommand.commandLine(SSHCommand.arguments(for: makeHost()))
    }

    static func newHost() -> SSHHostDraft { SSHHostDraft() }

    init() {}

    init(editing host: SSHHost) {
        hostID = host.id
        name = host.name
        hostName = host.hostName
        port = host.port.map(String.init) ?? ""
        user = host.user ?? ""
        authenticationMethod = host.authenticationMethod
        identityFile = host.identityFile ?? ""
        startupDirectory = host.startupDirectory ?? ""
        startupCommand = host.startupCommand ?? ""
        tags = host.tags.joined(separator: ", ")
        colorHex = host.colorHex ?? ""
        proxyJump = host.proxyJump ?? ""
        lastConnectedAt = host.lastConnectedAt
    }

    /// `~/.ssh/config` hostundan kayıtlı profil türetir ("Save as Profile").
    init(importing configHost: SSHConfigHost) {
        name = configHost.alias
        hostName = configHost.hostName ?? configHost.alias
        port = configHost.port.map(String.init) ?? ""
        user = configHost.user ?? ""
        // Anahtar YOLU taşınır, içeriği değil.
        if let identityFile = configHost.identityFile {
            authenticationMethod = .privateKey
            self.identityFile = identityFile
        }
        proxyJump = configHost.proxyJump ?? ""
    }

    func makeHost() -> SSHHost {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return SSHHost(id: hostID ?? UUID(),
                       name: trimmedName.isEmpty ? trimmedHost : trimmedName,
                       hostName: trimmedHost,
                       port: Int(port.trimmingCharacters(in: .whitespaces)).flatMap {
                           SSHCommand.isUsablePort($0) ? $0 : nil
                       },
                       user: SSHCommand.nonBlank(user),
                       authenticationMethod: authenticationMethod,
                       identityFile: SSHCommand.nonBlank(identityFile),
                       startupDirectory: SSHCommand.nonBlank(startupDirectory),
                       startupCommand: SSHCommand.nonBlank(startupCommand),
                       tags: SSHHostDraft.parseTags(tags),
                       colorHex: SSHCommand.nonBlank(colorHex),
                       proxyJump: SSHCommand.nonBlank(proxyJump),
                       lastConnectedAt: lastConnectedAt)
    }

    /// "prod, eu ,, prod" → ["prod", "eu"]: boşlar atılır, sıra korunarak tekilleşir.
    static func parseTags(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: ",").compactMap { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }
}

// MARK: - Ekran

/// Settings ▸ SSH (briefs/2 "SSH Yöneticisi", briefs/3 "SSH Ekranı").
///
/// Kompakt liste: brief sunucu kartlarının "aşırı büyük" olmamasını, yoğun bilgiyi az
/// yerde göstermesini istiyor. Kayıtlı profiller ve `~/.ssh/config` hostları ayrı
/// bölümlerde durur; config satırları salt okunurdur — o dosya kullanıcınındır.
struct SSHSettingsView: View {

    var hosts: SSHHostStore = .shared

    /// Hedefi yeni bir sekmede açan dikiş. Ayarlar penceresinin kendi terminali yoktur;
    /// bağlanma isteğini ancak dışarıdan verilen bu kapanış yerine getirebilir. Bağlı
    /// değilse satır yalnız "Copy Command" sunar (komut satırı panoya gider).
    var connect: ((SSHTarget) -> Void)?

    /// Testte sabitlenebilen saat.
    var now: () -> Date = Date.init

    @State private var draft: SSHHostDraft?
    @State private var copiedTargetID: String?

    var body: some View {
        VStack(spacing: 0) {
            if hosts.targets.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()
            footer
        }
        .onAppear { hosts.ensureConfigHostsLoaded() }
        .sheet(item: $draft) { presented in editorSheet(for: presented) }
    }

    // MARK: - Liste

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !hosts.hosts.isEmpty {
                    sectionHeader("Saved Hosts")
                    ForEach(hosts.hosts) { host in
                        row(for: .profile(host))
                    }
                }

                if !hosts.configHosts.isEmpty {
                    sectionHeader("From ~/.ssh/config")
                    ForEach(hosts.configHosts) { configHost in
                        row(for: .configHost(configHost))
                    }
                }
            }
            .padding(12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(for target: SSHTarget) -> some View {
        SSHHostRow(model: SSHHostRowModel.make(target: target, now: now()),
                   isCopied: copiedTargetID == target.id,
                   canConnect: connect != nil,
                   onConnect: { connect?(target) },
                   onCopy: { copyCommand(for: target) },
                   onEdit: { edit(target) },
                   onDelete: { delete(target) })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(SSHEmptyState.title)
                .font(.headline)
            Text(SSHEmptyState.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(SSHEmptyState.primaryActionTitle) { draft = .newHost() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack {
            Button {
                draft = .newHost()
            } label: {
                Label(SSHEmptyState.primaryActionTitle, systemImage: "plus")
            }
            .accessibilityLabel(SSHEmptyState.primaryActionTitle)

            Spacer()

            Button("Reload ~/.ssh/config") { hosts.reloadConfigHosts() }
                .accessibilityLabel("Reload hosts from ssh config")
        }
        .padding(12)
    }

    // MARK: - Eylemler

    /// Bağlanmanın panoya alınabilir hâli. Komut `SSHCommand` tarafından argüman argüman
    /// alıntılanır; panoya giden metinde birleştirme kaynaklı bir açık kalmaz.
    private func copyCommand(for target: SSHTarget) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(target.commandLine, forType: .string)
        copiedTargetID = target.id
    }

    private func edit(_ target: SSHTarget) {
        switch target {
        case let .profile(host):
            draft = SSHHostDraft(editing: host)
        case let .configHost(configHost):
            // Config satırı düzenlenmez; ondan KENDİ profilini türetir.
            draft = SSHHostDraft(importing: configHost)
        }
    }

    private func delete(_ target: SSHTarget) {
        guard case let .profile(host) = target else { return }
        hosts.remove(id: host.id)
    }

    /// Formu SUNULAN taslakla kurar.
    ///
    /// `Binding($draft)` (isteğe bağlıyı açan sarmalayıcı) BİLEREK kullanılmıyor: bu
    /// yüzeyde sayfanın içeriği boş çiziliyordu — kapanış, durum yazılmadan ÖNCEKİ
    /// görünüm değerini yakalayınca `if let` dalı hiç seçilmiyor ve kullanıcı boş bir
    /// sayfa görüyordu. Sayfanın kendi verdiği `presented` değeri her zaman doludur.
    private func editorSheet(for presented: SSHHostDraft) -> some View {
        let binding = Binding(get: { draft ?? presented }, set: { draft = $0 })
        return SSHHostEditorView(
            draft: binding,
            onSave: {
                hosts.upsert(binding.wrappedValue.makeHost())
                draft = nil
            },
            onCancel: { draft = nil })
        .frame(width: 520, height: 460)
    }
}

/// Tek satırlık kompakt kart (brief: "Sunucu kartları aşırı büyük tasarlanmamalıdır").
private struct SSHHostRow: View {
    let model: SSHHostRowModel
    let isCopied: Bool
    let canConnect: Bool
    let onConnect: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            colorDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    ForEach(model.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }

                Text(model.destinationText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                HStack(spacing: 6) {
                    Text(model.sourceText)
                    Text("·").foregroundStyle(.tertiary)
                    Text(model.lastConnectedText)
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isHovered, model.isEditable {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.editAccessibilityLabel)
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.deleteAccessibilityLabel)
            }

            // Geri bildirim metinle verilir; yalnız renk değişimiyle değil.
            Button(isCopied ? "Copied" : "Copy Command", action: onCopy)
                .accessibilityLabel(model.copyAccessibilityLabel)

            if canConnect {
                Button("Connect", action: onConnect)
                    .accessibilityLabel(model.connectAccessibilityLabel)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .motionAnimation(.hover, value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
    }

    @ViewBuilder
    private var colorDot: some View {
        // Renk yalnız İKİNCİL bir işarettir: satırdaki her bilgi metinle de yazılıdır.
        Circle()
            .fill(model.colorHex.flatMap { NSColor(hexString: $0) }.map { Color(nsColor: $0) }
                  ?? DesignTokens.textMuted.color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Form

/// SSH profili oluşturma/düzenleme formu (briefs/2 alan listesi).
struct SSHHostEditorView: View {

    @Binding var draft: SSHHostDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                connectionSection
                authenticationSection
                sessionSection
                organisationSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(draft.commandPreviewText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("Command preview")

                Spacer(minLength: 12)

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(draft.isEditingExistingHost ? "Save Changes" : "Create SSH Host",
                       action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isSaveEnabled)
            }
            .padding(12)
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            TextField("Display Name", text: $draft.name, prompt: Text("Production server"))
                .accessibilityLabel("Display Name")
            TextField("Host", text: $draft.hostName, prompt: Text("pinro.app"))
                .accessibilityLabel("Host")
            TextField("User", text: $draft.user, prompt: Text("deploy"))
                .accessibilityLabel("User")
            TextField("Port", text: $draft.port, prompt: Text("22"))
                .accessibilityLabel("Port")
            if let warning = draft.portWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.warning.color)
            }
            TextField("ProxyJump", text: $draft.proxyJump, prompt: Text("user@bastion"))
                .accessibilityLabel("Proxy Jump")
        }
    }

    private var authenticationSection: some View {
        Section("Authentication") {
            Picker("Method", selection: $draft.authenticationMethod) {
                ForEach(SSHAuthenticationMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .accessibilityLabel("Authentication Method")

            Text(draft.authenticationMethod.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.authenticationMethod == .privateKey {
                HStack(spacing: 8) {
                    TextField("Private Key Path", text: $draft.identityFile,
                              prompt: Text("~/.ssh/id_ed25519"))
                        .accessibilityLabel("Private Key Path")
                    Button("Choose…") { choosePrivateKey() }
                        .accessibilityLabel("Choose Private Key File")
                }
            }
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            TextField("Startup Directory", text: $draft.startupDirectory, prompt: Text("/srv/app"))
                .accessibilityLabel("Startup Directory")
            VStack(alignment: .leading, spacing: 4) {
                TextField("Startup Command", text: $draft.startupCommand, prompt: Text("docker compose ps"))
                    .accessibilityLabel("Startup Command")

                // Uzak sunucuda toplu silme briefs/2'nin riskli işlem listesinde; komut
                // uzakta çalıştığı için geri alma şansı yerelden de azdır.
                if let warning = DangerousCommand.inspect(draft.startupCommand) {
                    CommandRiskWarningLabel(warning: warning)
                }
            }
            Text("Runs on the remote host, then hands over an interactive shell.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var organisationSection: some View {
        Section("Organisation") {
            TextField("Tags", text: $draft.tags, prompt: Text("prod, eu"))
                .accessibilityLabel("Tags")
            Picker("Color", selection: $draft.colorHex) {
                Text("None").tag("")
                ForEach(DesignTokens.all) { token in
                    Text(token.name).tag(token.hex)
                }
            }
            .accessibilityLabel("Color")
        }
    }

    /// Yalnız YOL seçilir; dosyanın içeriği okunmaz ve hiçbir yere kopyalanmaz.
    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.identityFile = url.path
    }
}
