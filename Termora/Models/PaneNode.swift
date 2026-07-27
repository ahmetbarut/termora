import Foundation

/// Bölme ekseni. iTerm2 konvansiyonu: dikey bölme ayracı diktir, paneller yan yana durur.
enum SplitAxis: String, Codable {
    /// Dikey ayraç, paneller YAN YANA (⌘D).
    case vertical
    /// Yatay ayraç, paneller ÜST ÜSTE (⌘⇧D).
    case horizontal
}

/// Bir sekmenin panel yerleşimini tutan ikili ağaç.
/// Bu dosya M2'de yalnız veri tipini ve salt-okunur erişimcileri içerir;
/// bölme/kapatma/oran operasyonları M3'te (Task 14) eklenir.
indirect enum PaneNode: Equatable {
    case leaf(paneID: UUID, sessionID: UUID)
    case split(id: UUID, axis: SplitAxis, ratio: Double, first: PaneNode, second: PaneNode)

    /// Soldan sağa / üstten alta sırayla tüm yapraklar.
    var leaves: [(paneID: UUID, sessionID: UUID)] {
        switch self {
        case let .leaf(paneID, sessionID):
            return [(paneID: paneID, sessionID: sessionID)]
        case let .split(_, _, _, first, second):
            return first.leaves + second.leaves
        }
    }

    func sessionID(ofPane paneID: UUID) -> UUID? {
        leaves.first { $0.paneID == paneID }?.sessionID
    }
}