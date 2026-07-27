import Foundation
import Observation

/// Bir sekme: panel ağacı + aktif panel + başlık durumu.
/// Kalıcı değildir (oturum geri yükleme 2. fazda).
@Observable
final class TerminalTab: Identifiable {
    let id: UUID

    /// Kullanıcının elle verdiği ad. nil ise otomatik başlık gösterilir.
    var customTitle: String?

    /// Shell'in OSC ile bildirdiği başlık (SessionManager → TerminalSession → burası).
    var automaticTitle: String = ""

    var root: PaneNode
    var activePaneID: UUID
    var isSearchVisible: Bool = false

    /// Arama çubuğundaki metin ve seçenekler (sekme başına ayrı tutulur).
    var searchQuery = TerminalSearchQuery(term: "")
    /// Son `searchMatchSummary` sonucu; çubuktaki "2/14" sayacını besler.
    var searchSummary: SearchSummary = .empty

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return automaticTitle.isEmpty ? "Terminal" : automaticTitle
    }

    init(id: UUID = UUID(), root: PaneNode, activePaneID: UUID) {
        self.id = id
        self.root = root
        self.activePaneID = activePaneID
    }
}