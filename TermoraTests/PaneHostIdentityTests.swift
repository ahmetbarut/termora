import Foundation
import Testing
@testable import Termora

/// `PaneLeafView` panelin terminalini `.id(...)` ile kimliklendirir. İki sekme SwiftUI
/// ağacında AYNI yapısal konumu işgal ettiği için bu kimlik yalnız `restartGeneration`
/// olursa (taze her oturumda 0) SwiftUI önceki sekmenin NSView'ini yeniden kullanır ve
/// kullanıcı sekme değiştirince YANLIŞ terminali görür.
@Suite("Panel terminal kimliği")
struct PaneHostIdentityTests {

    @Test func differentSessionsGetDifferentIdentities() {
        let first = PaneHostIdentity(sessionID: UUID(), restartGeneration: 0)
        let second = PaneHostIdentity(sessionID: UUID(), restartGeneration: 0)
        #expect(first != second)
    }

    @Test func restartOfTheSameSessionChangesTheIdentity() {
        let sessionID = UUID()
        let before = PaneHostIdentity(sessionID: sessionID, restartGeneration: 0)
        let after = PaneHostIdentity(sessionID: sessionID, restartGeneration: 1)
        #expect(before != after)
    }

    @Test func identityIsStableForAnUnchangedSession() {
        let sessionID = UUID()
        let first = PaneHostIdentity(sessionID: sessionID, restartGeneration: 3)
        let second = PaneHostIdentity(sessionID: sessionID, restartGeneration: 3)
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }
}
