import AppKit

/// ⌘Q akışı: herhangi bir pencerede çalışan işlem varsa önce onay ister.
///
/// `.terminateLater` BİLEREK kullanılmadı: AppKit o yanıtta run loop'u
/// `NSModalPanelRunLoopMode`'a alıp `reply(toApplicationShouldTerminate:)` bekler ve
/// SwiftUI'nin `confirmationDialog`'u bu modda güvenilir biçimde çizilmez (uygulama
/// diyalog görünmeden asılı kalır). Bunun yerine `.terminateCancel` dönülür; onay gelince
/// kapanış `NSApp.terminate(nil)` ile yeniden başlatılır. Onaylanan pencerenin oturumları
/// kapandığı için o pencere artık meşgul değildir; sırada başka meşgul pencere varsa onun
/// için de onay istenir, hiçbiri kalmayınca `.terminateNow` dönülür (sonsuz döngü yok).
@MainActor
final class TermoraAppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator = WindowCloseCoordinator.firstBusy else { return .terminateNow }

        // Onay sheet'i o pencereye iliştiği için pencere öne getirilir.
        coordinator.bringWindowForward()

        let canTerminateNow = coordinator.requestTermination {
            // Diyalog kapanırken terminate() çağırmak sheet'i yarım bırakır.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return canTerminateNow ? .terminateNow : .terminateCancel
    }
}
