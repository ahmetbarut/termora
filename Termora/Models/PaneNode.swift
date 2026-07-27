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
extension PaneNode {

    /// Turns the target leaf into a 50/50 split; the old pane stays in `first`.
    /// Returns an unchanged tree when `paneID` is not present.
    func splitting(paneID: UUID, axis: SplitAxis, newPaneID: UUID, newSessionID: UUID) -> PaneNode {
        switch self {
        case let .leaf(id, sessionID):
            guard id == paneID else { return self }
            return .split(id: UUID(),
                          axis: axis,
                          ratio: 0.5,
                          first: .leaf(paneID: id, sessionID: sessionID),
                          second: .leaf(paneID: newPaneID, sessionID: newSessionID))

        case let .split(id, splitAxis, ratio, first, second):
            return .split(id: id,
                          axis: splitAxis,
                          ratio: ratio,
                          first: first.splitting(paneID: paneID, axis: axis,
                                                 newPaneID: newPaneID, newSessionID: newSessionID),
                          second: second.splitting(paneID: paneID, axis: axis,
                                                   newPaneID: newPaneID, newSessionID: newSessionID))
        }
    }

    /// Removes a pane; the sibling subtree replaces the parent split.
    /// Returns `nil` when the removed pane was the only leaf.
    func removing(paneID: UUID) -> PaneNode? {
        switch self {
        case let .leaf(id, _):
            return id == paneID ? nil : self

        case let .split(id, axis, ratio, first, second):
            let newFirst = first.removing(paneID: paneID)
            let newSecond = second.removing(paneID: paneID)
            switch (newFirst, newSecond) {
            case (nil, nil):
                return nil
            case let (nil, .some(remaining)):
                return remaining
            case let (.some(remaining), nil):
                return remaining
            case let (.some(lhs), .some(rhs)):
                return .split(id: id, axis: axis, ratio: ratio, first: lhs, second: rhs)
            }
        }
    }

    /// First leaf of the sibling subtree — the focus target after `paneID` is closed.
    func siblingLeafPaneID(of paneID: UUID) -> UUID? {
        switch self {
        case .leaf:
            return nil
        case let .split(_, _, _, first, second):
            if case let .leaf(id, _) = first, id == paneID {
                return second.leaves.first?.paneID
            }
            if case let .leaf(id, _) = second, id == paneID {
                return first.leaves.first?.paneID
            }
            if first.sessionID(ofPane: paneID) != nil {
                return first.siblingLeafPaneID(of: paneID) ?? second.leaves.first?.paneID
            }
            if second.sessionID(ofPane: paneID) != nil {
                return second.siblingLeafPaneID(of: paneID) ?? first.leaves.first?.paneID
            }
            return nil
        }
    }

    /// Allowed divider range; keeps both panes usable.
    static let ratioRange: ClosedRange<Double> = 0.15...0.85

    /// Updates one split's ratio, clamped to `ratioRange`. Other nodes are untouched.
    func updatingRatio(splitID: UUID, ratio: Double) -> PaneNode {
        switch self {
        case .leaf:
            return self

        case let .split(id, axis, currentRatio, first, second):
            if id == splitID {
                let clamped = min(max(ratio, PaneNode.ratioRange.lowerBound), PaneNode.ratioRange.upperBound)
                return .split(id: id, axis: axis, ratio: clamped, first: first, second: second)
            }
            return .split(id: id,
                          axis: axis,
                          ratio: currentRatio,
                          first: first.updatingRatio(splitID: splitID, ratio: ratio),
                          second: second.updatingRatio(splitID: splitID, ratio: ratio))
        }
    }
}
