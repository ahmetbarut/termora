import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct PaneNodeLeafTests {

    @Test func leafReturnsItselfAsOnlyLeaf() {
        let paneID = UUID()
        let sessionID = UUID()
        let node = PaneNode.leaf(paneID: paneID, sessionID: sessionID)

        #expect(node.leaves.count == 1)
        #expect(node.leaves[0].paneID == paneID)
        #expect(node.leaves[0].sessionID == sessionID)
    }

    @Test func leavesAreReturnedInFirstThenSecondOrder() {
        let a = (pane: UUID(), session: UUID())
        let b = (pane: UUID(), session: UUID())
        let c = (pane: UUID(), session: UUID())
        let node = PaneNode.split(
            id: UUID(),
            axis: .vertical,
            ratio: 0.5,
            first: .leaf(paneID: a.pane, sessionID: a.session),
            second: .split(
                id: UUID(),
                axis: .horizontal,
                ratio: 0.5,
                first: .leaf(paneID: b.pane, sessionID: b.session),
                second: .leaf(paneID: c.pane, sessionID: c.session)
            )
        )

        #expect(node.leaves.map(\.paneID) == [a.pane, b.pane, c.pane])
    }

    @Test func sessionIDOfPaneFindsMatchingLeafOrNil() {
        let a = (pane: UUID(), session: UUID())
        let b = (pane: UUID(), session: UUID())
        let node = PaneNode.split(
            id: UUID(),
            axis: .vertical,
            ratio: 0.5,
            first: .leaf(paneID: a.pane, sessionID: a.session),
            second: .leaf(paneID: b.pane, sessionID: b.session)
        )

        #expect(node.sessionID(ofPane: b.pane) == b.session)
        #expect(node.sessionID(ofPane: UUID()) == nil)
    }

    @Test func equalTreesCompareEqual() {
        let paneID = UUID()
        let sessionID = UUID()
        #expect(PaneNode.leaf(paneID: paneID, sessionID: sessionID)
                == PaneNode.leaf(paneID: paneID, sessionID: sessionID))
        #expect(PaneNode.leaf(paneID: paneID, sessionID: sessionID)
                != PaneNode.leaf(paneID: UUID(), sessionID: sessionID))
    }
}