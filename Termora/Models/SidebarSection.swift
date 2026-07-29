import Foundation

/// briefs/3 "Sidebar" bölümleri, brief'in saydığı sırayla.
///
/// Brief'in beş bölümü de burada. Bölüm listesi kayıt yokken de döner: kullanıcı SSH
/// hostu ya da kayıtlı komutu olmadığını görebilmeli.
enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case workspaces
    case folders
    case ssh
    case docker
    case savedCommands

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspaces: return "Workspaces"
        case .folders: return "Recent Folders"
        case .ssh: return "SSH Hosts"
        case .docker: return "Docker"
        case .savedCommands: return "Saved Commands"
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
        case .savedCommands: return .savedCommands
        }
    }

    /// briefs/3 "Empty State": tek cümle, gereksiz illüstrasyon yok.
    var emptyMessage: String {
        switch self {
        case .workspaces: return "No workspaces yet"
        case .folders: return "No folders opened yet"
        case .ssh: return "No SSH hosts found"
        case .docker: return "No containers running"
        case .savedCommands: return "No saved commands yet"
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
