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
    static func commandAccessibilityLabel(index: Int, total: Int, command: String) -> String {
        "Command \(index + 1) of \(total): \(command)"
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
