import XCTest

/// Spec §11 smoke testi: uygulama açılıyor, ⌘T sekme ekliyor, ⌘W sekmeyi kapatıyor.
/// Sekmeler TabBarView'ın verdiği "tab-<uuid>" accessibility identifier'ı ile sayılır.
///
/// NOT: Bu test, UI testine izin verilmeyen makinelerde koşmaz — XCTest runner
/// "Failed to initialize for UI testing: System authentication is running" ile düşer.
/// Bu bir kod hatası değildir; makineye erişilebilirlik izni verilmesi gerekir.
final class TabSmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLaunchesThenOpensAndClosesATab() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "Ana pencere 15 sn içinde açılmadı")
        XCTAssertTrue(waitForTabCount(1, in: app), "Açılışta tam olarak bir sekme beklenir")

        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(waitForTabCount(2, in: app), "⌘T ikinci sekmeyi açmadı")

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForTabCount(1, in: app), "⌘W sekmeyi kapatmadı")
    }

    // MARK: - Yardımcılar

    private func tabCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab-"))
            .count
    }

    private func waitForTabCount(_ expected: Int,
                                 in app: XCUIApplication,
                                 timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if tabCount(in: app) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
