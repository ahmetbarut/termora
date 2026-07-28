import Foundation

/// Bir workspace panelinin kalıcı tanımı.
/// Oturum kimliği YOKTUR: workspace açıldığında yeni shell'ler başlar (briefs/2).
struct WorkspacePane: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// nil → `Workspace.directory` kullanılır.
    var startupDirectory: String?
    /// Onay verilmedikçe çalıştırılmaz (briefs/2 güvenlik kuralı).
    var startupCommand: String?

    init(id: UUID = UUID(), startupDirectory: String? = nil, startupCommand: String? = nil) {
        self.id = id
        self.startupDirectory = startupDirectory
        self.startupCommand = startupCommand
    }
}

/// Kayıtlı bir sekme: kullanıcı adı + panel ağacı.
struct WorkspaceTab: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// Kullanıcının verdiği ad; nil → otomatik başlık.
    var title: String?
    var layout: WorkspaceLayout

    init(id: UUID = UUID(), title: String? = nil, layout: WorkspaceLayout) {
        self.id = id
        self.title = title
        self.layout = layout
    }
}

/// `PaneNode` ile aynı ağaç şekli, ama serileştirilebilir ve oturum kimliği içermez.
/// Split kimlikleri de saklanmaz: bunlar yalnız açık düzenin sürükleme hedefidir,
/// workspace açılırken yeniden üretilirler.
indirect enum WorkspaceLayout: Codable, Equatable {
    case pane(WorkspacePane)
    case split(axis: SplitAxis, ratio: Double, first: WorkspaceLayout, second: WorkspaceLayout)

    /// Soldan sağa / üstten alta sırayla tüm paneller.
    var panes: [WorkspacePane] {
        switch self {
        case let .pane(pane):
            return [pane]
        case let .split(_, _, first, second):
            return first.panes + second.panes
        }
    }
}

/// Belirli bir proje için terminal düzenini ve başlangıç komutlarını saklayan çalışma alanı.
struct Workspace: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    /// Proje klasörü; panel kendi dizinini bildirmediğinde buraya düşülür.
    var directory: String
    var tabs: [WorkspaceTab] = []
    var environment: [String: String] = [:]
    var profileID: UUID?
    var themeID: String?
    /// true → açılışta başlangıç komutları için onay sorulmaz.
    var trustsStartupCommands: Bool = false
    var lastOpenedAt: Date?

    /// Kartta gösterilen toplam panel sayısı.
    var paneCount: Int {
        tabs.reduce(0) { $0 + $1.layout.panes.count }
    }

    init(id: UUID = UUID(),
         name: String,
         directory: String,
         tabs: [WorkspaceTab] = [],
         environment: [String: String] = [:],
         profileID: UUID? = nil,
         themeID: String? = nil,
         trustsStartupCommands: Bool = false,
         lastOpenedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.directory = directory
        self.tabs = tabs
        self.environment = environment
        self.profileID = profileID
        self.themeID = themeID
        self.trustsStartupCommands = trustsStartupCommands
        self.lastOpenedAt = lastOpenedAt
    }
}
