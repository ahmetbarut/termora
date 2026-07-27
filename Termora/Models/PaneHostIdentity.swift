import Foundation

/// Bir panelde barındırılan terminalin SwiftUI kimliği.
///
/// `sessionID` kimliğin parçası OLMAK ZORUNDA: iki sekmenin kök paneli SwiftUI ağacında
/// aynı yapısal konumu işgal eder, bu yüzden kimlik yalnız `restartGeneration` olursa
/// (taze her oturumda 0) SwiftUI `makeNSView`'i yeniden çağırmaz ve önceki sekmenin
/// NSView'ini ekranda tutar — kullanıcı sekme değiştirdiğinde yanlış terminali görür.
///
/// `restartGeneration` de kimliğin parçasıdır: `SessionManager.restartSession` aynı oturum
/// kimliğinin arkasına YENİ bir NSView kurar, kimlik değişmezse ölü görünüm ekranda kalır.
struct PaneHostIdentity: Hashable {
    let sessionID: UUID
    let restartGeneration: Int
}
