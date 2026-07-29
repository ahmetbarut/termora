import Foundation
import SwiftTerm

/// Imlec stilinin kalici (Codable) karsiligi. `rawValue`'lar kalicilik sozlesmesidir,
/// degistirilirse kayitli ayarlar okunamaz.
enum CursorStyleSetting: String, Codable, CaseIterable {
    case blinkBlock
    case steadyBlock
    case blinkUnderline
    case steadyUnderline
    case blinkBar
    case steadyBar

    var swiftTermStyle: SwiftTerm.CursorStyle {
        switch self {
        case .blinkBlock: return .blinkBlock
        case .steadyBlock: return .steadyBlock
        case .blinkUnderline: return .blinkUnderline
        case .steadyUnderline: return .steadyUnderline
        case .blinkBar: return .blinkBar
        case .steadyBar: return .steadyBar
        }
    }
}

/// Uygulama genelindeki kullanici ayarlari. `SettingsStore` tarafindan UserDefaults'a
/// JSON olarak yazilir; yeni alanlar varsayilan degerle eklenmelidir ki eski bloblar
/// cozulmeye devam etsin.
struct AppSettings: Codable, Equatable {
    /// brief 3 "Tipografi": varsayilan terminal fontu SF Mono 13 pt, satir yuksekligi 1.25.
    /// SF Mono kurulu degilse `FontCatalog.resolvedFont` sistem monospace fontuna,
    /// o da yoksa Menlo'ya duser — geri dusus zinciri korunur.
    var fontName: String? = DesignTokens.Typography.terminalFontFamily
    var fontSize: Double = DesignTokens.Typography.terminalFontSize
    var lineSpacing: Double = DesignTokens.Typography.terminalLineHeight
    var cursorStyle: CursorStyleSetting = .blinkBlock
    /// brief 3 "Tipografi": ligature açılıp kapatılabilmelidir.
    ///
    /// Varsayılan KAPALI. SwiftTerm bir satırı tek `CTLine` olarak çizip glyph'leri
    /// `sütun × glyphIndex` ile konumlandırır; ligature iki karakteri tek glyph'e
    /// indirdiğinde satırın geri kalanı bir sütun kayar. Fira Code ve JetBrains Mono
    /// font listesinde önerildiği için bu sessiz bir hizalama hatası olurdu.
    var usesLigatures: Bool = false
    var themeID: String = "termora-dark"
    var windowOpacity: Double = 1.0
    var scrollbackLines: Int = 10_000
    var defaultShellPath: String? = nil
    var startupDirectory: String? = nil
    var showStatusBar: Bool = true
    /// briefs/3 "Sidebar": varsayılan kapalı. Yeni kullanıcı yalnız terminali görmeli
    /// (briefs/3 "Aşamalı Karmaşıklık"); workspace, SSH ve Docker istendiğinde açılır.
    var isSidebarVisible: Bool = false
    /// briefs/2 "Komut Blokları": *Komut blokları zorunlu olmamalı; ayarlardan klasik
    /// terminal görünümüne geçilebilmelidir.*
    ///
    /// Varsayılan KAPALI ve panel terminalin YERİNE geçmez, yanında durur. Blok görünümü
    /// terminali değiştirseydi `vim`, `top`, `tmux` gibi tam ekran uygulamalar bozulurdu
    /// (briefs/2 kabul kriteri: *Interactive uygulamaların görünümü bozulmuyor*).
    var isCommandBlockPanelVisible: Bool = false

    /// briefs/3 "Yeni Sekme Ekranı": *Yeni sekme açıldığında shell doğrudan
    /// başlatılmalıdır.* Launcher yalnız kullanıcı isterse araya girer, bu yüzden
    /// varsayılan KAPALI — ve brief ayrıca "terminal kullanımını yavaşlatmamalı" diyor.
    var showsNewTabLauncher: Bool = false

    /// briefs/3 "Ses Kullanımı": açık olan sesler. Boş küme = tamamen sessiz, yani
    /// varsayılan. Kapalı olanları da yazmak yerine yalnız AÇIK olanları saklamak,
    /// eksik verinin sessizliğe düşmesini garanti eder.
    var enabledSounds: Set<String> = []

    /// Sesi kapalı tutan kullanıcı için bell'in görsel karşılığı.
    var usesVisualBell: Bool = false

    /// briefs/2 "Hata Raporlama": isteğe bağlı çökme raporu. Varsayılan KAPALI ve
    /// eksik kayıt da kapalı sayılır — eksik veri asla raporlamayı kendiliğinden
    /// açmamalı (briefs/2 "Gizlilik": telemetri varsayılan olarak kapalıdır).
    var sendsCrashReports: Bool = false

    /// briefs/2 "Güncelleme Sistemi": otomatik kontrol AÇIK gelir.
    ///
    /// Kapalı bir varsayılan, güvenlik düzeltmesini kaçıran bir kullanıcı demektir.
    /// Kontrolün NE gönderdiği ayrı bir sorudur ve yanıtı `UpdaterConfiguration`da:
    /// makine profili hiçbir koşulda gönderilmez.
    var checksForUpdatesAutomatically: Bool = true

    /// Kontrol sıklığı (briefs/2 "Ayarlar Ekranı" ▸ Updates).
    var updateCheckInterval: UpdateCheckInterval = .daily

    /// briefs/2 "Ayarlar Ekranı" ▸ Keybindings: kullanıcının değiştirdiği kısayollar.
    ///
    /// Anahtar komut KİMLİĞİ (`AppShortcut.id`), değer `AppShortcut.stroke` biçimi.
    /// Yalnız DEĞİŞTİRİLENLER saklanır: varsayılanları da yazmak, uygulamanın kısayolu
    /// bir gün değiştiğinde kullanıcıyı eskisine kilitlerdi.
    var customShortcutStrokes: [String: String] = [:]
    var sidebarWidth: Double = SettingsLimits.defaultSidebarWidth
    /// brief 3 "İlk Açılış Akışı": ilk açılış akışı yalnızca bir kez gösterilir.
    /// Akış tamamlandığında **ve atlandığında** true olur.
    var hasCompletedOnboarding: Bool = false
    /// briefs/2 "Oturum Geri Yükleme": önceki oturum İSTEĞE BAĞLI geri yüklenir.
    /// Varsayılan KAPALI — açıkken uygulama, açık pencerelerin çalışma dizinlerini
    /// diske yazar; bu, kullanıcının açıkça istemesi gereken bir iz bırakmadır.
    var restoresPreviousSession: Bool = false

    /// briefs/2 "Bildirimler": uzun süren bir işlem bittiğinde İSTEĞE BAĞLI bildirim.
    ///
    /// Varsayılan KAPALI. İki gerekçe: (1) briefs/3 "Ses Kullanımı" uygulamanın varsayılan
    /// olarak sessiz olmasını istiyor ve bildirim de sessizliğin bir parçası; (2) ilk bildirim
    /// macOS izin sayfasını açar — kullanıcının istemediği bir özellik için sistem izni sormak
    /// kabalıktır. Kullanıcı anahtarı açtığında izin sorusunu kendisi davet etmiş olur.
    var notifiesOnLongCommands: Bool = false

    /// briefs/2: başarılı ve başarısız işlemler AYRI ayarlanabilir. Ana anahtar açıkken
    /// ikisi de açık gelir — "bildir" diyen kullanıcı sessizlik değil bildirim bekler.
    ///
    /// Çıkış durumu gözlenemeyen komutlar (bugün hepsi, bkz. `CommandOutcome`) bu anahtara
    /// bağlıdır: Termora başarısızlığı KANITLAYAMADIĞI için onları "başarısız" filtresine
    /// koymak, yalnız hataları duymak isteyen kullanıcıya her komutu bildirmek olurdu.
    var notifiesOnCommandSuccess: Bool = true
    var notifiesOnCommandFailure: Bool = true

    /// Bu süreden KISA işlemler bildirilmez (briefs/2). Saniye.
    var longCommandThresholdSeconds: Double = CommandNotificationLimits.defaultThreshold

    // MARK: - AI (briefs/2 "AI Asistanı")

    /// Ollama sunucusunun adresi. Yerel çalışır ve API anahtarı İSTEMEZ — bu yüzden
    /// burada saklanabilir, Keychain'e gerek yoktur (saklanan bir sır yok).
    var aiEndpoint: String = OllamaEndpoint.defaultAddress

    /// Kullanıcının seçtiği model. `nil`: henüz seçilmemiş ya da seçilen silinmiş.
    /// Termora bir model ADI uydurmaz; liste sunucudan gelir.
    var aiModel: String? = nil

    /// AI'a hangi bağlamların gönderileceği (briefs/2 "Terminal Bağlamı").
    var aiContext: AIContextPreferences = AIContextPreferences()

    /// briefs/2 "AI Asistanı": OpenAI, Anthropic, Ollama, OpenAI uyumlu özel adres.
    ///
    /// Varsayılan YEREL Ollama: yeni kullanıcı hiçbir anahtar girmeden ve hiçbir veri
    /// makineden çıkmadan başlar (briefs/2 "Gizlilik").
    var aiProviderKind: AIProviderKind = .ollama

    /// Sağlayıcı başına adres. Tek bir alan olsaydı OpenAI'ye geçip geri dönen kullanıcı
    /// Ollama adresini yeniden yazmak zorunda kalırdı.
    ///
    /// Anahtar `AIProviderKind.rawValue`; ham dize kullanılıyor çünkü sözlüğün JSON'a
    /// yazılması gerekiyor ve ileride kaldırılan bir sağlayıcının kaydı diğerlerini
    /// çözülemez hâle getirmemeli.
    var aiEndpointsByProvider: [String: String] = [:]

    /// Sağlayıcı başına seçili model. Modeller sağlayıcıya özgüdür; `llama3.2` OpenAI'de,
    /// `gpt-4o` Ollama'da yoktur.
    var aiModelsByProvider: [String: String] = [:]

    init() {}

    /// Elle yazılmış çözücü: Swift'in ürettiği `init(from:)` eksik anahtarlarda
    /// varsayılan değere DÜŞMEZ, `keyNotFound` fırlatır. Sentezlenmiş hâlde kalsaydı
    /// yeni bir alan eklemek, diskteki eski blobu `SettingsStore` gözünde bozuk yapar
    /// ve kullanıcının tüm ayarları sıfırlanırdı. Her alan `decodeIfPresent` ile okunur.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? defaults.fontName
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? defaults.lineSpacing
        // Ham değer üzerinden okunur: ileride eklenen bir imleç stili (`RawValue` eşleşmez)
        // enum'a doğrudan çözdürülseydi TÜM ayarlar çözülemez, `SettingsStore` blob'u
        // yedeğe atar ve kullanıcının her ayarı sıfırlanırdı. Yalnız bu alan düşer.
        cursorStyle = try container.decodeIfPresent(String.self, forKey: .cursorStyle)
            .flatMap(CursorStyleSetting.init(rawValue:)) ?? defaults.cursorStyle
        usesLigatures = try container.decodeIfPresent(Bool.self, forKey: .usesLigatures) ?? defaults.usesLigatures
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID) ?? defaults.themeID
        windowOpacity = try container.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? defaults.windowOpacity
        scrollbackLines = try container.decodeIfPresent(Int.self, forKey: .scrollbackLines) ?? defaults.scrollbackLines
        defaultShellPath = try container.decodeIfPresent(String.self, forKey: .defaultShellPath)
        startupDirectory = try container.decodeIfPresent(String.self, forKey: .startupDirectory)
        showStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? defaults.showStatusBar
        isSidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .isSidebarVisible)
            ?? defaults.isSidebarVisible
        isCommandBlockPanelVisible = try container.decodeIfPresent(
            Bool.self, forKey: .isCommandBlockPanelVisible
        ) ?? defaults.isCommandBlockPanelVisible
        customShortcutStrokes = try container.decodeIfPresent(
            [String: String].self, forKey: .customShortcutStrokes
        ) ?? defaults.customShortcutStrokes
        showsNewTabLauncher = try container.decodeIfPresent(
            Bool.self, forKey: .showsNewTabLauncher
        ) ?? defaults.showsNewTabLauncher
        enabledSounds = try container.decodeIfPresent(Set<String>.self, forKey: .enabledSounds)
            ?? defaults.enabledSounds
        usesVisualBell = try container.decodeIfPresent(Bool.self, forKey: .usesVisualBell)
            ?? defaults.usesVisualBell
        sendsCrashReports = try container.decodeIfPresent(Bool.self, forKey: .sendsCrashReports)
            ?? defaults.sendsCrashReports
        checksForUpdatesAutomatically = try container.decodeIfPresent(
            Bool.self, forKey: .checksForUpdatesAutomatically) ?? defaults.checksForUpdatesAutomatically
        updateCheckInterval = try container.decodeIfPresent(
            UpdateCheckInterval.self, forKey: .updateCheckInterval) ?? defaults.updateCheckInterval
        sidebarWidth = SettingsLimits.clampSidebarWidth(
            try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? defaults.sidebarWidth
        )
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? defaults.hasCompletedOnboarding
        // Güvenlik/gizlilik: bayrak eksikse KAPALI kabul edilir. Eksik veri asla oturum
        // kaydını kendiliğinden açmamalı.
        restoresPreviousSession = try container.decodeIfPresent(Bool.self, forKey: .restoresPreviousSession)
            ?? defaults.restoresPreviousSession
        // Aynı gerekçe: bayrak eksikse KAPALI. Güncelleyen kullanıcıya, istemediği bir özellik
        // için macOS bildirim izni sorusu kendiliğinden çıkmamalı.
        notifiesOnLongCommands = try container.decodeIfPresent(Bool.self, forKey: .notifiesOnLongCommands)
            ?? defaults.notifiesOnLongCommands
        notifiesOnCommandSuccess = try container.decodeIfPresent(Bool.self, forKey: .notifiesOnCommandSuccess)
            ?? defaults.notifiesOnCommandSuccess
        notifiesOnCommandFailure = try container.decodeIfPresent(Bool.self, forKey: .notifiesOnCommandFailure)
            ?? defaults.notifiesOnCommandFailure
        longCommandThresholdSeconds = try container.decodeIfPresent(Double.self, forKey: .longCommandThresholdSeconds)
            ?? defaults.longCommandThresholdSeconds
        aiEndpoint = try container.decodeIfPresent(String.self, forKey: .aiEndpoint) ?? defaults.aiEndpoint
        // Bilinmeyen bir sağlayıcı adı (eski/yeni sürüm) yalnız KENDİ kaydını düşürür;
        // tüm ayarları çözülemez yapmaz.
        aiProviderKind = try container.decodeIfPresent(String.self, forKey: .aiProviderKind)
            .flatMap(AIProviderKind.init(rawValue:)) ?? defaults.aiProviderKind
        aiEndpointsByProvider = try container.decodeIfPresent(
            [String: String].self, forKey: .aiEndpointsByProvider
        ) ?? defaults.aiEndpointsByProvider
        aiModelsByProvider = try container.decodeIfPresent(
            [String: String].self, forKey: .aiModelsByProvider
        ) ?? defaults.aiModelsByProvider

        aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel)

        // Tek sağlayıcılı sürümden göç: o sürümde `aiEndpoint`/`aiModel` Ollama'nın
        // kaydıydı. Boşluğu YALNIZ doldurur — sağlayıcı başına kayıt varsa ona
        // dokunmaz, yoksa güncelleme kullanıcının yeni ayarını eskisiyle ezerdi.
        let ollama = AIProviderKind.ollama.rawValue
        if aiEndpointsByProvider[ollama] == nil, aiEndpoint != defaults.aiEndpoint {
            aiEndpointsByProvider[ollama] = aiEndpoint
        }
        if aiModelsByProvider[ollama] == nil, let aiModel {
            aiModelsByProvider[ollama] = aiModel
        }
        // Bağlam tercihleri KENDİ ileri uyumlu çözücüsüne sahiptir; ileride eklenen bir
        // bağlam türü eski blobu bozmaz. Blok tamamen bozuksa varsayılana düşer —
        // gizlilik açısından güvenli yön budur (varsayılanlar geçmişi göndermiyor).
        aiContext = (try? container.decodeIfPresent(AIContextPreferences.self, forKey: .aiContext))
            .flatMap { $0 } ?? defaults.aiContext
    }
}


// MARK: - Sağlayıcı başına AI ayarları

extension AppSettings {

    /// Seçili sağlayıcının adresi; kullanıcı girmediyse sağlayıcının resmî adresi.
    /// Özel adresli sağlayıcıda boş döner — orada adres yalnızca kullanıcıdan gelir.
    func aiEndpoint(for kind: AIProviderKind) -> String {
        if let stored = aiEndpointsByProvider[kind.rawValue], !stored.isEmpty { return stored }
        return kind.defaultEndpoint ?? ""
    }

    mutating func aiEndpoint(for kind: AIProviderKind, is value: String) {
        aiEndpointsByProvider[kind.rawValue] = value
    }

    func aiModel(for kind: AIProviderKind) -> String? {
        aiModelsByProvider[kind.rawValue]
    }

    mutating func aiModel(for kind: AIProviderKind, is value: String?) {
        aiModelsByProvider[kind.rawValue] = value
    }
}


// MARK: - Ses ayarları (briefs/3 "Ses Kullanımı")

extension AppSettings {
    func isSoundEnabled(_ event: SoundEvent) -> Bool {
        enabledSounds.contains(event.rawValue)
    }

    mutating func setSoundEnabled(_ event: SoundEvent, _ isEnabled: Bool) {
        if isEnabled { enabledSounds.insert(event.rawValue) }
        else { enabledSounds.remove(event.rawValue) }
    }
}
