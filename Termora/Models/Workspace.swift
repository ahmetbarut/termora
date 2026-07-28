import Foundation
import os

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

    private enum CodingKeys: String, CodingKey {
        case id, startupDirectory, startupCommand
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

    private enum CodingKeys: String, CodingKey {
        case id, title, layout
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

    private enum CodingKeys: String, CodingKey {
        case id, name, directory, tabs, environment, profileID, themeID, trustsStartupCommands, lastOpenedAt
    }
}

// MARK: - İleri uyumlu çözme
//
// Sentezlenmiş `init(from:)` özellik varsayılanlarını YOK SAYAR: alan JSON'da yoksa
// `keyNotFound` fırlatır. Bu yüzden bu ağaçtaki her tip kendi çözücüsünü yazar ve her
// isteğe bağlı alanı `decodeIfPresent` ile okur. Aksi hâlde modele eklenen tek bir yeni
// alan, kullanıcının diskteki tüm workspace'lerini `WorkspaceStore` gözünde bozuk yapardı.
//
// Ortak kural: gerçek varsayılanı OLMAYAN alan (kimlikler, ad, dizin, düzen) için değer
// UYDURULMAZ. Böyle bir alan eksikse o KAYIT çözülemez ve çağıran onu atlar; liste ve
// ağacın geri kalanı korunur.

extension WorkspacePane {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startupDirectory = try container.decodeIfPresent(String.self, forKey: .startupDirectory)
        startupCommand = try container.decodeIfPresent(String.self, forKey: .startupCommand)
    }
}

extension WorkspaceTab {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        // Düzen uydurulmaz: boş bir sekme, kullanıcının panellerini ve başlangıç
        // komutlarını sessizce yutardı.
        layout = try container.decode(WorkspaceLayout.self, forKey: .layout)
    }
}

extension WorkspaceLayout {
    /// Kalıcılık sözleşmesi: bu anahtarlar Swift'in enum'lar için ürettiği JSON şeklinin
    /// AYNISIDIR (`{"pane":{"_0":{…}}}`, `{"split":{"axis":…}}`). Diskteki blob'lar bu
    /// şekille yazıldı; değiştirilirse tüm kayıtlı workspace'ler okunamaz hâle gelir.
    private enum CaseKey: String, CodingKey {
        case pane, split
    }

    private enum PaneKey: String, CodingKey {
        case _0
    }

    private enum SplitKey: String, CodingKey {
        case axis, ratio, first, second
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        if container.contains(.pane) {
            let nested = try container.nestedContainer(keyedBy: PaneKey.self, forKey: .pane)
            self = .pane(try nested.decode(WorkspacePane.self, forKey: ._0))
            return
        }
        if container.contains(.split) {
            let nested = try container.nestedContainer(keyedBy: SplitKey.self, forKey: .split)
            // Eksen ve oran yalnız GEOMETRİDİR, veri değil: eksiklerse varsayılana düşmek
            // hiçbir paneli kaybettirmez. ⌘D'nin ürettiği yan yana bölme varsayılandır.
            let axis = try nested.decodeIfPresent(SplitAxis.self, forKey: .axis) ?? .vertical
            let ratio = try nested.decodeIfPresent(Double.self, forKey: .ratio) ?? 0.5
            self = .split(axis: axis,
                          ratio: ratio,
                          first: try nested.decode(WorkspaceLayout.self, forKey: .first),
                          second: try nested.decode(WorkspaceLayout.self, forKey: .second))
            return
        }
        // Bilinmeyen case (ör. ileride eklenen üçlü bölme): YAKLAŞTIRILMAZ. Tek panele
        // indirgemek kullanıcının panellerini ve başlangıç komutlarını sessizce silerdi.
        // Fırlatıyoruz; `Workspace` yalnız bu sekmeyi atlar, diğer sekmeler kalır.
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Unknown WorkspaceLayout case; expected \"pane\" or \"split\""))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case let .pane(pane):
            var nested = container.nestedContainer(keyedBy: PaneKey.self, forKey: .pane)
            try nested.encode(pane, forKey: ._0)
        case let .split(axis, ratio, first, second):
            var nested = container.nestedContainer(keyedBy: SplitKey.self, forKey: .split)
            try nested.encode(axis, forKey: .axis)
            try nested.encode(ratio, forKey: .ratio)
            try nested.encode(first, forKey: .first)
            try nested.encode(second, forKey: .second)
        }
    }
}

extension Workspace {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Kimlik, ad ve dizin uydurulamaz: taze bir UUID `upsert` kimliğini ve açık
        // pencerelerin bağını koparır, uydurma ad/dizin kullanıcıya yanlış bilgi verir.
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        directory = try container.decode(String.self, forKey: .directory)
        // Tek bozuk sekme workspace'i düşürmez; çözülebilen sekmeler korunur.
        let decodedTabs = try container.decodeIfPresent(LenientArray<WorkspaceTab>.self, forKey: .tabs)
        if let failures = decodedTabs?.failures, !failures.isEmpty {
            // Logger burada yerel olarak üretilir: `Codable` çözücüsü nonisolated'dır,
            // MainActor'a bağlanan static/global bir alana dokunamaz.
            Logger(subsystem: "com.ahmetbarut.Termora", category: "WorkspaceDecoding")
                .error("""
                    Skipped \(failures.count, privacy: .public) undecodable tab(s) while loading a workspace: \
                    \(decodedTabs?.failureSummary ?? "", privacy: .public)
                    """)
        }
        tabs = decodedTabs?.elements ?? []
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID)
        // Güvenlik: güven bayrağı eksikse GÜVENİLMEZ kabul edilir; eksik veri asla
        // başlangıç komutlarının sorulmadan çalışmasına yol açmamalı.
        trustsStartupCommands = try container.decodeIfPresent(Bool.self, forKey: .trustsStartupCommands) ?? false
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }
}
