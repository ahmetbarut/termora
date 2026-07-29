import Foundation

/// briefs/3 "Sidebar" bölümleri, brief'in saydığı sırayla.
///
/// Saved Commands brief'te beşinci bölüm olarak geçer; özelliğin kendisi henüz yok
/// (#25). Boş bir bölüm çizmek yerine, özellik geldiğinde buraya eklenecek.
enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case workspaces
    case folders
    case ssh
    case docker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspaces: return "Workspaces"
        case .folders: return "Recent Folders"
        case .ssh: return "SSH Hosts"
        case .docker: return "Docker"
        }
    }

    var symbolName: String { paletteCategory.symbolName }

    /// Sidebar kendi kayıtlarını toplamaz; komut paletinin bu kategorideki öğelerini
    /// gösterir. Tek kaynak olduğu için iki yüzey ayrışamaz.
    var paletteCategory: CommandPaletteCategory {
        switch self {
        case .workspaces: return .workspaces
        case .folders: return .folders
        case .ssh: return .ssh
        case .docker: return .docker
        }
    }

    /// briefs/3 "Empty State": tek cümle, gereksiz illüstrasyon yok.
    var emptyMessage: String {
        switch self {
        case .workspaces: return "No workspaces yet"
        case .folders: return "No folders opened yet"
        case .ssh: return "No SSH hosts found"
        case .docker: return "No containers running"
        }
    }
}

/// Tek bir sidebar bölümü ve içindeki komutlar.
struct SidebarSectionContent: Identifiable {
    let section: SidebarSection
    let items: [CommandPaletteItem]

    var id: String { section.id }
}

enum SidebarCatalog {

    /// Palet öğelerini sidebar bölümlerine dağıtır. Bölümler kayıt yokken de döner:
    /// kullanıcı SSH hostu olmadığını görebilmeli, boş sidebar'ın sebebini
    /// tahmin etmek zorunda kalmamalı.
    static func sections(from items: [CommandPaletteItem]) -> [SidebarSectionContent] {
        SidebarSection.allCases.map { section in
            SidebarSectionContent(
                section: section,
                items: items.filter { $0.category == section.paletteCategory }
            )
        }
    }
}
