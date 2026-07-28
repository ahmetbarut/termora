import Foundation
import Testing
@testable import Termora

/// Riskli komutun KULLANICIYA görünen yüzü (briefs/2 "Tehlikeli Komut Koruması" +
/// "Erişilebilirlik → renk tek durum göstergesi olamaz").
///
/// Workspace açılış onayı bir `confirmationDialog` mesajıdır: orada renk, kalın yazı ya da
/// SF Symbol YOKTUR, yalnız düz metin vardır. Bu yüzden işaret metnin kendisine girer.
@Suite("Riskli komutun sunumu")
@MainActor
struct CommandRiskPresentationTests {

    // MARK: - Onay diyaloğundaki komut satırı

    @Test func aSafeCommandIsShownExactlyAsTheUserWroteIt() {
        #expect(WorkspaceLaunchPrompt.commandLine("npm run dev") == "npm run dev")
        #expect(WorkspaceLaunchPrompt.commandLine("php artisan serve") == "php artisan serve")
    }

    @Test func aRiskyCommandIsMarkedWithASymbolAndWordsNotWithColour() {
        let line = WorkspaceLaunchPrompt.commandLine("rm -rf /")
        #expect(line.contains(WorkspaceLaunchPrompt.riskMarker))
        #expect(line.contains(CommandRisk.high.label))
        // Komutun kendisi kaybolmaz: kullanıcı NE çalışacağını görmeden onay veremez.
        #expect(line.contains("rm -rf /"))
        #expect(!WorkspaceLaunchPrompt.riskMarker.isEmpty)
    }

    @Test func theTwoRiskLevelsAreDistinguishableInPlainText() {
        let high = WorkspaceLaunchPrompt.commandLine("rm -rf /")
        let caution = WorkspaceLaunchPrompt.commandLine("git reset --hard")
        #expect(high != caution)
        #expect(caution.contains(CommandRisk.caution.label))
        #expect(!caution.contains(CommandRisk.high.label))
    }

    // MARK: - Diyaloğun gövdesi

    @Test func theBodyKeepsTheHeaderAndListsEveryCommand() {
        let body = WorkspaceLaunchPrompt.messageBody(commands: ["npm run dev", "php artisan serve"])
        #expect(body.contains(WorkspaceLaunchPrompt.message(commandCount: 2)))
        #expect(body.contains("npm run dev"))
        #expect(body.contains("php artisan serve"))
    }

    @Test func theBodyStaysQuietWhenNothingIsRisky() {
        let body = WorkspaceLaunchPrompt.messageBody(commands: ["npm run dev"])
        #expect(!body.contains(WorkspaceLaunchPrompt.riskFooter))
        #expect(!body.contains(WorkspaceLaunchPrompt.riskMarker))
    }

    @Test func theBodyExplainsTheMarkWhenSomethingIsRisky() {
        let body = WorkspaceLaunchPrompt.messageBody(commands: ["npm run dev", "rm -rf /"])
        #expect(body.contains(WorkspaceLaunchPrompt.riskFooter))
        #expect(body.contains(WorkspaceLaunchPrompt.riskMarker))
        #expect(body.contains("npm run dev"))
    }

    @Test func anEmptyCommandListProducesNoDanglingMarkers() {
        let body = WorkspaceLaunchPrompt.messageBody(commands: [])
        #expect(!body.contains(WorkspaceLaunchPrompt.riskMarker))
        #expect(body.contains(WorkspaceLaunchPrompt.message(commandCount: 0)))
    }

    // MARK: - VoiceOver

    @Test func theSpokenCommandLineAddsTheRiskSentence() throws {
        let label = WorkspaceLaunchPrompt.commandAccessibilityLabel(index: 0, total: 2, command: "rm -rf /")
        let warning = try #require(DangerousCommand.inspect("rm -rf /"))
        #expect(label.contains("Command 1 of 2"))
        #expect(label.contains("rm -rf /"))
        #expect(label.contains(warning.message))
        #expect(label.contains(CommandRisk.high.accessibilityLabel))
    }

    @Test func aSafeCommandIsSpokenWithoutAWarning() {
        let label = WorkspaceLaunchPrompt.commandAccessibilityLabel(index: 1, total: 2, command: "npm run dev")
        #expect(label == "Command 2 of 2: npm run dev")
    }
}
