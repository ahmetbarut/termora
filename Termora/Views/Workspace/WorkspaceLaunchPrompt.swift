import Foundation

/// Başlangıç komutu onayının metni (briefs/2 güvenlik kuralı + briefs/3 "Uygulama Metin Dili").
///
/// Kullanıcı NE çalışacağını görmeden karar veremez: komutlar ayrıca listelenir, düğmeler
/// eylemi adlandırır ve belirsiz `OK`/`Yes` kullanılmaz.
enum WorkspaceLaunchPrompt {

    static func title(workspaceName: String) -> String {
        "Run startup commands for “\(WorkspaceCardModel.displayName(workspaceName))”?"
    }

    static func message(commandCount: Int) -> String {
        "Termora runs \(Pluralize.count(commandCount, "command")) in this workspace before you start using it."
    }

    /// Komut listesinin başlığı.
    static let commandListTitle = "Commands"

    static let runTitle = "Run Commands"
    static let skipTitle = "Open Without Commands"
    static let cancelTitle = "Cancel"

    static let allButtonTitles = [runTitle, skipTitle, cancelTitle]

    static let trustToggleTitle = "Always trust this workspace"
    static let trustToggleHelp = "Startup commands for this workspace run without asking from now on."

    /// VoiceOver: komut satırları tek tek okunurken kaçıncı komut olduğu söylenir.
    /// Riskli komutta seviye ve sonuç aynı cümlede duyulur — işaret yalnız GÖRSEL olamaz.
    static func commandAccessibilityLabel(index: Int, total: Int, command: String) -> String {
        let base = "Command \(index + 1) of \(total): \(command)"
        guard let warning = DangerousCommand.inspect(command) else { return base }
        return "\(base). \(warning.accessibilityLabel)"
    }

    // MARK: - Riskli komutun işareti (briefs/2 "Tehlikeli Komut Koruması")

    /// Onay bir `confirmationDialog` mesajıdır: orada renk, kalınlık ya da SF Symbol
    /// YOKTUR, yalnız düz metin vardır. Bu yüzden işaret metnin içine girer — simge
    /// karakteri + seviyeyi adlandıran sözcük.
    static let riskMarker = "⚠"

    static let riskFooter = "Marked commands can destroy data. Review them before you run them."

    static func commandLine(_ command: String) -> String {
        guard let warning = DangerousCommand.inspect(command) else { return command }
        return "\(riskMarker) \(warning.label): \(command)"
    }

    /// Diyaloğun tam gövdesi: kaç komut çalışacağı + komutların kendisi (riskliler işaretli)
    /// + yalnız gerçekten risk varsa açıklama satırı.
    static func messageBody(commands: [String]) -> String {
        var lines = [message(commandCount: commands.count), ""]
        lines.append(contentsOf: commands.map(commandLine))
        if commands.contains(where: { DangerousCommand.inspect($0) != nil }) {
            lines.append("")
            lines.append(riskFooter)
        }
        return lines.joined(separator: "\n")
    }
}

/// Ana pencerede AYNI ANDA kaç onay çizilebileceğine karar veren saf kural.
///
/// Kapatma onayı ve workspace başlatma onayı iki ayrı sunum katmanıdır; ikisi birden
/// açılırsa macOS ikinciyi yutar ve bekleyen kapatma eylemi (pencere kapatma geri çağrısı)
/// sessizce kaybolur. Karar tek bir yerde verilir ve testle kilitlenir.
enum WorkspaceDialogPresentation: Equatable {
    case none
    case closeConfirmation
    case startupCommands

    static func current(hasPendingClose: Bool, hasPendingLaunch: Bool) -> WorkspaceDialogPresentation {
        if hasPendingClose { return .closeConfirmation }
        if hasPendingLaunch { return .startupCommands }
        return .none
    }
}

/// "Open Without Commands" için workspace'in komutsuz KOPYASI.
///
/// Kayıt diskte değişmez; yalnız bu açılış komutsuz yapılır. Panel ve sekme kimlikleri
/// korunur — `WorkspaceViewModel.openWorkspace` açılıştan sonra kaydı kimliğiyle
/// damgalar, kimlik değişseydi damga hiçbir kayda düşmezdi.
enum WorkspaceStartupCommands {

    static func removingStartupCommands(from workspace: Workspace) -> Workspace {
        var copy = workspace
        copy.tabs = workspace.tabs.map { tab in
            var tab = tab
            tab.layout = clearing(tab.layout)
            return tab
        }
        return copy
    }

    private static func clearing(_ layout: WorkspaceLayout) -> WorkspaceLayout {
        switch layout {
        case .pane(var pane):
            pane.startupCommand = nil
            return .pane(pane)
        case let .split(axis, ratio, first, second):
            return .split(axis: axis, ratio: ratio, first: clearing(first), second: clearing(second))
        }
    }
}
