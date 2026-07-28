import Foundation

/// "Son açılma zamanı" metni (briefs/3, workspace kartı).
///
/// `RelativeDateTimeFormatter` bilerek kullanılmaz: çıktısı sistem diline ve takvimine göre
/// değişir, arayüz metinleri ise İngilizce ve sabit olmalıdır (briefs/3 "Uygulama Metin Dili").
enum WorkspaceRelativeTime {

    /// Hiç açılmamış workspace boş bırakılmaz.
    static let neverText = "Never opened"

    private static let minute: Double = 60
    private static let hour: Double = 60 * 60
    private static let day: Double = 24 * 60 * 60
    private static let week: Double = 7 * 24 * 60 * 60
    private static let month: Double = 30 * 24 * 60 * 60
    private static let year: Double = 365 * 24 * 60 * 60

    static func text(lastOpenedAt: Date?, now: Date) -> String {
        guard let lastOpenedAt else { return neverText }
        // Saat geri alınmışsa gelecek bir damga oluşur; "-3 dakika önce" yazmak yerine
        // en yakın anlamlı ifadeye düşülür.
        let elapsed = max(0, now.timeIntervalSince(lastOpenedAt))

        switch elapsed {
        case ..<minute: return "Opened just now"
        case ..<hour: return opened(Int(elapsed / minute), "minute")
        case ..<day: return opened(Int(elapsed / hour), "hour")
        case ..<week: return opened(Int(elapsed / day), "day")
        case ..<month: return opened(Int(elapsed / week), "week")
        case ..<year: return opened(Int(elapsed / month), "month")
        default: return opened(Int(elapsed / year), "year")
        }
    }

    private static func opened(_ count: Int, _ unit: String) -> String {
        "Opened \(Pluralize.count(count, unit)) ago"
    }
}

/// "1 tab" / "3 tabs" gibi sayı+ad birleşimleri tek yerden üretilir.
enum Pluralize {
    static func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(plural ?? singular + "s")"
    }
}

/// briefs/3 "Workspace Ekranı" kartının TÜM metni.
///
/// Görünüm katmanı bu değerleri olduğu gibi çizer; hiçbir metin `body` içinde kurulmaz.
/// Böylece "aşırı büyük kart" yerine yoğun bilgili kompakt satır tek yerde tanımlanır ve
/// VoiceOver etiketleri görünen bilgiyle senkron kalır.
struct WorkspaceCardModel: Equatable, Identifiable {

    /// Adsız kayıt hem listede hem VoiceOver'da sessiz kalmaz.
    static let untitledName = "Untitled Workspace"
    /// Klasörü olmayan (elle bozulmuş) kayıt boş bir satır göstermez.
    static let noFolderText = "No folder selected"
    /// Depo rozeti: dal ikonu. Rozet metinle birlikte çizilir, renk tek sinyal değildir.
    static let repositorySymbolName = "arrow.triangle.branch"
    /// Güven rozeti; "Trusted" metniyle birlikte kullanılır.
    static let trustedSymbolName = "checkmark.shield"

    let id: UUID
    let name: String
    let pathText: String
    /// "3 tabs" / "1 tab" / "No tabs".
    let tabsText: String
    /// "5 panes"; panel yoksa nil (çizilecek rozet yok).
    let panesText: String?
    /// "2 startup commands"; komut yoksa nil.
    let startupCommandsText: String?
    /// "termora · main"; klasör bir depo değilse nil.
    let repositoryText: String?
    /// "Trusted"; onaysız çalışacak komut yoksa nil.
    let trustText: String?
    let lastOpenedText: String
    /// Satırın tamamının konuşulan hâli.
    let accessibilityLabel: String
    let launchAccessibilityLabel: String
    let editAccessibilityLabel: String
    let deleteAccessibilityLabel: String

    static func make(workspace: Workspace,
                     repository: GitRepositoryInfo?,
                     now: Date,
                     home: String) -> WorkspaceCardModel {
        let name = displayName(workspace.name)
        let directory = workspace.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathText = directory.isEmpty ? noFolderText : PathDisplay.abbreviate(directory, home: home)

        let tabCount = workspace.tabs.count
        let tabsText = tabCount == 0 ? "No tabs" : Pluralize.count(tabCount, "tab")
        let paneCount = workspace.paneCount
        let panesText = paneCount == 0 ? nil : Pluralize.count(paneCount, "pane")

        let commandCount = WorkspaceOpenPlan.startupCommands(for: workspace).count
        let startupCommandsText = commandCount == 0
            ? nil
            : Pluralize.count(commandCount, "startup command")

        let repositoryText = repository.map { info in
            guard let branch = info.branch, !branch.isEmpty else { return info.repositoryName }
            return "\(info.repositoryName) · \(branch)"
        }

        // Güven rozeti yalnız güvenilecek bir şey varken anlamlıdır: komutsuz bir
        // workspace zaten hiç onay sormaz.
        let trustText = (workspace.trustsStartupCommands && commandCount > 0) ? "Trusted" : nil

        let lastOpenedText = WorkspaceRelativeTime.text(lastOpenedAt: workspace.lastOpenedAt, now: now)

        var spoken: [String] = [name, pathText, tabsText]
        if let panesText { spoken.append(panesText) }
        if let startupCommandsText { spoken.append(startupCommandsText) }
        if let repository {
            if let branch = repository.branch, !branch.isEmpty {
                spoken.append("repository \(repository.repositoryName) on branch \(branch)")
            } else {
                spoken.append("repository \(repository.repositoryName)")
            }
        }
        if trustText != nil { spoken.append("startup commands run without asking") }
        spoken.append(lastOpenedText)

        return WorkspaceCardModel(
            id: workspace.id,
            name: name,
            pathText: pathText,
            tabsText: tabsText,
            panesText: panesText,
            startupCommandsText: startupCommandsText,
            repositoryText: repositoryText,
            trustText: trustText,
            lastOpenedText: lastOpenedText,
            accessibilityLabel: spoken.joined(separator: ", "),
            launchAccessibilityLabel: "Open workspace \(name)",
            editAccessibilityLabel: "Edit workspace \(name)",
            deleteAccessibilityLabel: "Delete workspace \(name)")
    }

    /// Boş ya da yalnız boşluktan oluşan ad okunur bir yedeğe düşer.
    static func displayName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitledName : trimmed
    }
}

/// briefs/3 "Empty State": tek cümlelik açıklama + birincil eylem; illüstrasyon yok.
enum WorkspacesEmptyState {
    static let title = "No workspaces yet"
    static let message = "A workspace reopens a project's tabs, panes and folders in one step."
    static let primaryActionTitle = "New Workspace"
}
