import Foundation

/// briefs/2 "Lisanslama ve Planlar"ın iki planı.
///
/// Brief'in en bağlayıcı cümlesi burada uygulanıyor: *Temel terminal özellikleri ücret
/// duvarının arkasına konulmamalıdır.* Free listesi `isFreeTier` ile sabit ve bir Pro
/// kontrolü onların önüne geçemez.
nonisolated enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    // Free (briefs/2)
    case localTerminals
    case tabs
    case splitTerminals
    case themes
    case search
    case profiles
    // Pro (briefs/2)
    case workspaces
    case sshManager
    case aiAssistant
    case dockerTools
    case commandBlocks
    case sessionRestore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localTerminals: "Local terminals"
        case .tabs: "Tabs"
        case .splitTerminals: "Split terminals"
        case .themes: "Themes"
        case .search: "Search"
        case .profiles: "Profiles"
        case .workspaces: "Workspaces"
        case .sshManager: "SSH manager"
        case .aiAssistant: "AI assistant"
        case .dockerTools: "Docker tools"
        case .commandBlocks: "Command blocks"
        case .sessionRestore: "Session restore"
        }
    }

    /// Ücretsiz planın kapsamı. Bu liste brief'ten gelir ve daraltılamaz.
    var isFreeTier: Bool {
        switch self {
        case .localTerminals, .tabs, .splitTerminals, .themes, .search, .profiles: true
        default: false
        }
    }

    /// Kilitli özellik GİZLENMEZ, kendini anlatır: kullanıcı neyi kaçırdığını bilmeli.
    var lockedExplanation: String {
        switch self {
        case .workspaces: "Save a project's tabs, layout and startup commands, then reopen them together."
        case .sshManager: "Keep your hosts in one place and connect without retyping them."
        case .aiAssistant: "Ask about a command or an error without leaving the terminal."
        case .dockerTools: "Open a shell in a container or follow its logs from the palette."
        case .commandBlocks: "See each command with its output, duration and exit code."
        case .sessionRestore: "Reopen the windows and folders you had when you quit."
        default: ""
        }
    }
}

/// Lisans durumu.
nonisolated enum LicenseState: Equatable, Sendable {
    case free
    case pro

    /// briefs/1 "Güvenlik": anahtar Keychain'de. `AppSettings`'te anahtar için alan
    /// yoktur — ayarlar diske düz JSON yazıldığı için oraya düşen bir anahtar sızıntı olur.
    static let keychainAccount = "license.key"

    /// briefs/2: doğrulama çevrimdışı yapılır.
    ///
    /// Sunucuya soran bir doğrulama, uçakta ya da güvenlik duvarı arkasındaki bir
    /// kullanıcının kendi satın aldığı özelliği kaybetmesi demektir — ve terminal
    /// uygulaması tam olarak o ortamlarda kullanılır.
    static let verificationIsOffline = true

    /// Doğrulanmış lisans varsa Pro, yoksa Free.
    init(license: License?) {
        self = license == nil ? .free : .pro
    }

    func allows(_ feature: ProFeature) -> Bool {
        // Ücretsiz özellik HER ZAMAN açık: bir Pro kontrolü brief'in "ücret duvarı
        // olmayacak" kuralının önüne geçemez.
        if feature.isFreeTier { return true }
        return self == .pro
    }
}
