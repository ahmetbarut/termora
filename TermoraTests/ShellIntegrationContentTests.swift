import Foundation
import Testing
@testable import Termora

/// Ayarlar ▸ General ▸ Shell ve onboarding'de görünen shell integration metinleri.
///
/// Metinler `body` dışında tutuluyor (proje kalıbı: `AISettingsContent`,
/// `OnboardingAIContent`): kullanıcının dotfile'ına yazan bir özelliğin ne yaptığını
/// SÖYLEYEN cümleler testle sabitlenmeli.
@Suite("Shell integration metinleri")
struct ShellIntegrationContentTests {

    /// Kullanıcı hangi dosyaya yazılacağını ÖNCEDEN bilmeli; onay ancak bilgiyle olur.
    @Test func theExplanationNamesTheFileItWillTouch() {
        #expect(ShellIntegrationContent.explanation(for: .zsh).contains(".zshrc"))
        #expect(ShellIntegrationContent.explanation(for: .bash).contains(".bash_profile"))
    }

    /// Ne işe yaradığı söylenir: yoksa "dotfile'ıma neden yazıyorsun" sorusunun cevabı yok.
    @Test func theExplanationSaysWhatTermoraGainsFromIt() {
        let text = ShellIntegrationContent.explanation(for: .zsh).lowercased()
        #expect(text.contains("exit code"))
    }

    /// Geri alınabilirlik AÇIKÇA yazılır — dotfile'a yazan bir özellikte en çok merak
    /// edilen budur.
    @Test func theExplanationPromisesItCanBeRemoved() {
        #expect(ShellIntegrationContent.explanation(for: .zsh).lowercased().contains("remove"))
    }

    /// Düğme eylemi ADLANDIRIR (briefs/3 "Uygulama Metin Dili"): belirsiz "OK" yok.
    @Test func theButtonsNameTheirAction() {
        #expect(ShellIntegrationContent.installTitle == "Install Shell Integration")
        #expect(ShellIntegrationContent.uninstallTitle == "Remove Shell Integration")
    }

    /// Kurulum yalnız YENİ kabuklarda etkindir; kullanıcı hiçbir şey olmadığını sanıp
    /// tekrar tekrar basmasın.
    @Test func theInstalledStateSaysWhenItTakesEffect() {
        let text = ShellIntegrationContent.installedNote.lowercased()
        #expect(text.contains("new") || text.contains("restart") || text.contains("reopen"))
    }

    /// Desteklenmeyen kabukta düğme gösterilmez; yerine DÜRÜST bir cümle kalır.
    @Test func anUnsupportedShellGetsASentenceNotADeadButton() {
        let text = ShellIntegrationContent.unsupportedShellNote(shellPath: "/opt/homebrew/bin/fish")
        #expect(text.contains("fish"))
        #expect(text.lowercased().contains("zsh"))
        #expect(text.hasSuffix("."))
    }

    @Test func everySentenceIsFinished() {
        let all = [ShellIntegrationContent.explanation(for: .zsh),
                   ShellIntegrationContent.explanation(for: .bash),
                   ShellIntegrationContent.installedNote,
                   ShellIntegrationContent.unsupportedShellNote(shellPath: "/bin/ksh")]
        for sentence in all {
            #expect(!sentence.isEmpty)
            #expect(sentence.hasSuffix("."), "bitmemiş cümle: \(sentence)")
        }
    }
}
