import Foundation

/// Workspace editörünün bölümleri, briefs/3'teki adım sırasıyla:
/// 1) proje klasörü 2) terminal düzeni 3) başlangıç komutları — ve ayrı tutulan
/// gelişmiş ayarlar ("Gelişmiş ayarlar ilk ekranda gösterilmemelidir").
enum WorkspaceEditorSection: CaseIterable {
    case folder
    case layout
    case commands
    case advanced

    var title: String {
        switch self {
        case .folder: return "Project Folder"
        case .layout: return "Terminal Layout"
        case .commands: return "Startup Commands"
        case .advanced: return "Advanced"
        }
    }

    var symbolName: String {
        switch self {
        case .folder: return "folder"
        case .layout: return "rectangle.split.2x1"
        case .commands: return "terminal"
        case .advanced: return "slider.horizontal.3"
        }
    }

    /// Yalnız gelişmiş ayarlar kapalı başlar; ilk üç adım akışın kendisidir.
    var isCollapsedByDefault: Bool { self == .advanced }
}

/// Workspace oluşturma/düzenleme formunun SAF durumu.
///
/// Görünüm yalnız bu değeri bağlar: doğrulama, adın klasörden türetilmesi, panel etiketleri
/// ve kaydetme dönüşümü burada yaşar. Kayıt kimliği taslak boyunca sabittir — aynı formu
/// iki kez kaydetmek depoda ikinci bir kopya üretmez.
struct WorkspaceDraft: Equatable {

    /// Kullanıcı ada dokunduğu anda ad artık klasörü izlemez (bkz. `nameFollowsDirectory`).
    var name: String {
        didSet { nameFollowsDirectory = false }
    }
    private(set) var directory: String
    private(set) var tabs: [WorkspaceTab]
    /// briefs/3: gelişmiş bölümde durur, varsayılanı KAPALI (onay sorulur).
    var trustsStartupCommands: Bool

    /// Formun hiç göstermediği ama kaybolmaması gereken alanlar.
    private var environment: [String: String]
    private var profileID: UUID?
    private var themeID: String?
    private var lastOpenedAt: Date?

    private let workspaceID: UUID
    let isEditingExistingWorkspace: Bool

    /// Ad hâlâ klasörden türemişse (kullanıcı elle değiştirmediyse) klasörü izler.
    private var nameFollowsDirectory: Bool

    // MARK: - Kurulum

    static func newWorkspace() -> WorkspaceDraft {
        WorkspaceDraft(name: "",
                       directory: "",
                       tabs: [WorkspaceTab(layout: .pane(WorkspacePane()))],
                       trustsStartupCommands: false,
                       environment: [:],
                       profileID: nil,
                       themeID: nil,
                       lastOpenedAt: nil,
                       workspaceID: UUID(),
                       isEditingExistingWorkspace: false,
                       nameFollowsDirectory: true)
    }

    init(editing workspace: Workspace) {
        self.init(name: workspace.name,
                  directory: workspace.directory,
                  // Boş düzenli bir kayıt düzenlenirken form panelsiz kalmaz.
                  tabs: workspace.tabs.isEmpty
                      ? [WorkspaceTab(layout: .pane(WorkspacePane()))]
                      : workspace.tabs,
                  trustsStartupCommands: workspace.trustsStartupCommands,
                  environment: workspace.environment,
                  profileID: workspace.profileID,
                  themeID: workspace.themeID,
                  lastOpenedAt: workspace.lastOpenedAt,
                  workspaceID: workspace.id,
                  isEditingExistingWorkspace: true,
                  nameFollowsDirectory: false)
    }

    private init(name: String,
                 directory: String,
                 tabs: [WorkspaceTab],
                 trustsStartupCommands: Bool,
                 environment: [String: String],
                 profileID: UUID?,
                 themeID: String?,
                 lastOpenedAt: Date?,
                 workspaceID: UUID,
                 isEditingExistingWorkspace: Bool,
                 nameFollowsDirectory: Bool) {
        self.name = name
        self.directory = directory
        self.tabs = tabs
        self.trustsStartupCommands = trustsStartupCommands
        self.environment = environment
        self.profileID = profileID
        self.themeID = themeID
        self.lastOpenedAt = lastOpenedAt
        self.workspaceID = workspaceID
        self.isEditingExistingWorkspace = isEditingExistingWorkspace
        self.nameFollowsDirectory = nameFollowsDirectory
    }

    // MARK: - 1. Adım: proje klasörü

    /// Klasör seçildi. Ad boşsa ya da hâlâ önceki klasörden türemişse klasörü izler;
    /// kullanıcının yazdığı ad ASLA ezilmez.
    mutating func chooseDirectory(_ path: String) {
        let cleaned = Self.normalizedDirectory(path)
        let shouldSeedName = nameFollowsDirectory
            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        directory = cleaned
        guard shouldSeedName else { return }
        name = Self.suggestedName(forDirectory: cleaned)
        // `name`'in didSet'i bayrağı düşürür; tohumlanan ad klasörü izlemeye DEVAM etmeli.
        nameFollowsDirectory = true
    }

    var isSaveEnabled: Bool {
        !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sondaki `/` atılır: `/Users/dev/api/` klasör adını boş bırakırdı.
    static func normalizedDirectory(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    static func suggestedName(forDirectory path: String) -> String {
        (normalizedDirectory(path) as NSString).lastPathComponent
    }

    // MARK: - 2. Adım: terminal düzeni

    var paneCount: Int { tabs.reduce(0) { $0 + $1.layout.panes.count } }

    /// Kartla aynı dili konuşur: "2 tabs · 3 panes".
    var layoutSummary: String {
        "\(Pluralize.count(tabs.count, "tab")) · \(Pluralize.count(paneCount, "pane"))"
    }

    /// Açık pencerenin düzenini benimser ("Use Current Layout").
    /// Boş yakalama yok sayılır: kapalı bir pencere taslağı silmemeli.
    /// Yazılmış komutlar panel SIRASINA göre yeni düzene taşınır.
    mutating func useLayout(from capturedTabs: [WorkspaceTab]) {
        guard !capturedTabs.isEmpty else { return }
        let carried = tabs.flatMap { $0.layout.panes.map(\.startupCommand) }
        var index = 0
        tabs = capturedTabs.map { tab in
            var tab = tab
            tab.layout = Self.mapping(tab.layout) { pane in
                var pane = pane
                pane.startupCommand = index < carried.count ? carried[index] : nil
                index += 1
                return pane
            }
            return tab
        }
    }

    // MARK: - 3. Adım: başlangıç komutları

    /// Formda tek bir metin alanına karşılık gelen panel.
    struct PaneEditor: Equatable, Identifiable {
        let paneID: UUID
        /// "Server · Pane 2" ya da tek panelli sekmede "Server" / "Tab 2".
        let label: String
        /// Boş metin "komut yok" demektir; modelde nil olarak saklanır.
        let command: String

        var id: UUID { paneID }

        /// briefs/3: alan etiketi hangi panele ait olduğunu söylemeli.
        var accessibilityLabel: String { "Startup command for \(label)" }
    }

    var paneEditors: [PaneEditor] {
        tabs.enumerated().flatMap { tabIndex, tab -> [PaneEditor] in
            let panes = tab.layout.panes
            let tabLabel = tab.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Tab \(tabIndex + 1)"
            return panes.enumerated().map { paneIndex, pane in
                PaneEditor(paneID: pane.id,
                           label: panes.count == 1 ? tabLabel : "\(tabLabel) · Pane \(paneIndex + 1)",
                           command: pane.startupCommand ?? "")
            }
        }
    }

    mutating func setStartupCommand(_ command: String, paneID: UUID) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        tabs = tabs.map { tab in
            var tab = tab
            tab.layout = Self.mapping(tab.layout) { pane in
                guard pane.id == paneID else { return pane }
                var pane = pane
                pane.startupCommand = trimmed.isEmpty ? nil : trimmed
                return pane
            }
            return tab
        }
    }

    var startupCommandCount: Int {
        tabs.flatMap { $0.layout.panes }.compactMap(\.startupCommand).count
    }

    // MARK: - 4. Adım: kaydet

    func makeWorkspace() -> Workspace {
        Workspace(id: workspaceID,
                  name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                  directory: Self.normalizedDirectory(directory),
                  tabs: tabs,
                  environment: environment,
                  profileID: profileID,
                  themeID: themeID,
                  trustsStartupCommands: trustsStartupCommands,
                  lastOpenedAt: lastOpenedAt)
    }

    // MARK: - Ağaç yürüyüşü

    /// Düzen ağacındaki her paneli dönüştürür; split kimlikleri ve oranlar korunur.
    private static func mapping(_ layout: WorkspaceLayout,
                                _ transform: (WorkspacePane) -> WorkspacePane) -> WorkspaceLayout {
        switch layout {
        case let .pane(pane):
            return .pane(transform(pane))
        case let .split(axis, ratio, first, second):
            return .split(axis: axis,
                          ratio: ratio,
                          first: mapping(first, transform),
                          second: mapping(second, transform))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
