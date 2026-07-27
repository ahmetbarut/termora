//
//  PaneNodeTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

@Suite("PaneNode")
struct PaneNodeTests {

    // MARK: - Helpers

    private func makeLeaf() -> (node: PaneNode, paneID: UUID, sessionID: UUID) {
        let paneID = UUID()
        let sessionID = UUID()
        return (.leaf(paneID: paneID, sessionID: sessionID), paneID, sessionID)
    }

    private func splitID(of node: PaneNode) -> UUID? {
        if case let .split(id, _, _, _, _) = node { return id }
        return nil
    }

    // MARK: - splitting

    @Test("splitting hedef leaf'i 0.5 oranlı split'e çevirir, eski panel first'te kalır")
    func splittingConvertsTargetLeaf() {
        let (node, paneID, sessionID) = makeLeaf()
        let newPaneID = UUID()
        let newSessionID = UUID()

        let result = node.splitting(paneID: paneID,
                                    axis: .vertical,
                                    newPaneID: newPaneID,
                                    newSessionID: newSessionID)

        guard case let .split(_, axis, ratio, first, second) = result else {
            Issue.record("split bekleniyordu, gelen: \(result)")
            return
        }
        #expect(axis == .vertical)
        #expect(ratio == 0.5)
        #expect(first == .leaf(paneID: paneID, sessionID: sessionID))
        #expect(second == .leaf(paneID: newPaneID, sessionID: newSessionID))
    }

    @Test("iç içe bölme yalnız hedef leaf'i etkiler")
    func splittingNested() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()

        let root = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
        let twoPanes = root.splitting(paneID: paneA, axis: .vertical,
                                      newPaneID: paneB, newSessionID: sessionB)
        let threePanes = twoPanes.splitting(paneID: paneB, axis: .horizontal,
                                            newPaneID: paneC, newSessionID: sessionC)

        guard case let .split(_, outerAxis, _, outerFirst, outerSecond) = threePanes else {
            Issue.record("dış split bekleniyordu")
            return
        }
        #expect(outerAxis == .vertical)
        #expect(outerFirst == .leaf(paneID: paneA, sessionID: sessionA))

        guard case let .split(_, innerAxis, innerRatio, innerFirst, innerSecond) = outerSecond else {
            Issue.record("iç split bekleniyordu")
            return
        }
        #expect(innerAxis == .horizontal)
        #expect(innerRatio == 0.5)
        #expect(innerFirst == .leaf(paneID: paneB, sessionID: sessionB))
        #expect(innerSecond == .leaf(paneID: paneC, sessionID: sessionC))
    }

    // MARK: - leaves / sessionID

    @Test("leaves soldan sağa (first→second) sırayı korur")
    func leavesOrder() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()

        let tree = PaneNode.split(
            id: UUID(), axis: .vertical, ratio: 0.5,
            first: .split(id: UUID(), axis: .horizontal, ratio: 0.5,
                          first: .leaf(paneID: paneA, sessionID: sessionA),
                          second: .leaf(paneID: paneB, sessionID: sessionB)),
            second: .leaf(paneID: paneC, sessionID: sessionC))

        #expect(tree.leaves.map { $0.paneID } == [paneA, paneB, paneC])
        #expect(tree.leaves.map { $0.sessionID } == [sessionA, sessionB, sessionC])
    }

    @Test("sessionID(ofPane:) doğru oturumu bulur, bilinmeyen panel için nil döner")
    func sessionLookup() {
        let (leaf, paneID, sessionID) = makeLeaf()
        let newPaneID = UUID(), newSessionID = UUID()
        let tree = leaf.splitting(paneID: paneID, axis: .horizontal,
                                  newPaneID: newPaneID, newSessionID: newSessionID)

        #expect(tree.sessionID(ofPane: paneID) == sessionID)
        #expect(tree.sessionID(ofPane: newPaneID) == newSessionID)
        #expect(tree.sessionID(ofPane: UUID()) == nil)
    }

// MARK: - removing

    @Test("removing kardeşi ebeveynin yerine yükseltir")
    func removingPromotesSibling() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)

        #expect(tree.removing(paneID: paneB) == .leaf(paneID: paneA, sessionID: sessionA))
        #expect(tree.removing(paneID: paneA) == .leaf(paneID: paneB, sessionID: sessionB))
    }

    @Test("derin ağaçta removing yalnız ilgili alt ağacı sadeleştirir")
    func removingInNestedTree() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()
        let outerID = UUID()

        let tree = PaneNode.split(
            id: outerID, axis: .vertical, ratio: 0.4,
            first: .leaf(paneID: paneA, sessionID: sessionA),
            second: .split(id: UUID(), axis: .horizontal, ratio: 0.5,
                           first: .leaf(paneID: paneB, sessionID: sessionB),
                           second: .leaf(paneID: paneC, sessionID: sessionC)))

        let result = tree.removing(paneID: paneC)
        #expect(result == .split(id: outerID, axis: .vertical, ratio: 0.4,
                                 first: .leaf(paneID: paneA, sessionID: sessionA),
                                 second: .leaf(paneID: paneB, sessionID: sessionB)))
    }

    @Test("kökteki tek leaf kaldırılırsa nil döner")
    func removingLastLeafReturnsNil() {
        let (node, paneID, _) = makeLeaf()
        #expect(node.removing(paneID: paneID) == nil)
    }

    @Test("bilinmeyen panel kaldırılınca ağaç değişmez")
    func removingUnknownPaneKeepsTree() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)

        #expect(tree.removing(paneID: UUID()) == tree)
    }

    // MARK: - siblingLeafPaneID

    @Test("siblingLeafPaneID kardeş alt ağacın ilk yaprağını verir")
    func siblingLookup() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()

        // split( split(A, B), C ) — B'nin kardeşi A'dır, leaves sırasında bir SONRAKİ eleman C olsa bile.
        let tree = PaneNode.split(
            id: UUID(), axis: .vertical, ratio: 0.5,
            first: .split(id: UUID(), axis: .horizontal, ratio: 0.5,
                          first: .leaf(paneID: paneA, sessionID: sessionA),
                          second: .leaf(paneID: paneB, sessionID: sessionB)),
            second: .leaf(paneID: paneC, sessionID: sessionC))

        #expect(tree.siblingLeafPaneID(of: paneB) == paneA)
        #expect(tree.siblingLeafPaneID(of: paneA) == paneB)
        #expect(tree.siblingLeafPaneID(of: paneC) == paneA)   // C'nin kardeşi split(A,B) → ilk yaprak A
        #expect(tree.siblingLeafPaneID(of: UUID()) == nil)
        #expect(PaneNode.leaf(paneID: paneA, sessionID: sessionA).siblingLeafPaneID(of: paneA) == nil)
    }

// MARK: - updatingRatio

    @Test("updatingRatio hedef split'in oranını değiştirir")
    func updatingRatioChangesTarget() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)
        guard let id = splitID(of: tree) else {
            Issue.record("split id okunamadı")
            return
        }

        let updated = tree.updatingRatio(splitID: id, ratio: 0.3)
        guard case let .split(_, _, ratio, _, _) = updated else {
            Issue.record("split bekleniyordu")
            return
        }
        #expect(ratio == 0.3)
    }

    @Test("updatingRatio oranı 0.15...0.85 aralığına kırpar")
    func updatingRatioClamps() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let tree = PaneNode.leaf(paneID: paneA, sessionID: sessionA)
            .splitting(paneID: paneA, axis: .vertical, newPaneID: paneB, newSessionID: sessionB)
        guard let id = splitID(of: tree) else {
            Issue.record("split id okunamadı")
            return
        }

        var ratios: [Double] = []
        for candidate in [-1.0, 0.0, 0.15, 0.5, 0.85, 1.0, 4.2] {
            if case let .split(_, _, ratio, _, _) = tree.updatingRatio(splitID: id, ratio: candidate) {
                ratios.append(ratio)
            }
        }
        #expect(ratios == [0.15, 0.15, 0.15, 0.5, 0.85, 0.85, 0.85])
    }

    @Test("updatingRatio iç split'i bulur, bilinmeyen id ağacı değiştirmez")
    func updatingRatioNestedAndUnknown() {
        let paneA = UUID(), sessionA = UUID()
        let paneB = UUID(), sessionB = UUID()
        let paneC = UUID(), sessionC = UUID()
        let innerID = UUID()

        let tree = PaneNode.split(
            id: UUID(), axis: .vertical, ratio: 0.4,
            first: .leaf(paneID: paneA, sessionID: sessionA),
            second: .split(id: innerID, axis: .horizontal, ratio: 0.5,
                           first: .leaf(paneID: paneB, sessionID: sessionB),
                           second: .leaf(paneID: paneC, sessionID: sessionC)))

        let updated = tree.updatingRatio(splitID: innerID, ratio: 0.7)
        guard case let .split(_, _, outerRatio, _, second) = updated,
              case let .split(_, _, innerRatio, _, _) = second else {
            Issue.record("iç içe split bekleniyordu")
            return
        }
        #expect(outerRatio == 0.4)
        #expect(innerRatio == 0.7)

        #expect(tree.updatingRatio(splitID: UUID(), ratio: 0.7) == tree)
    }
}
