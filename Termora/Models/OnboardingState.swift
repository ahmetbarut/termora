import Foundation
import Observation

/// brief 3 "İlk Açılış Akışı" üç ekran tanımlar; uzun ürün turu yoktur.
enum OnboardingStep: Int, CaseIterable, Identifiable, Comparable {
    case welcome
    case appearance
    case finish

    var id: Int { rawValue }

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Brief'te ekran 1 ve 3 için metin birebir verilmiştir. Ara adımda belirsiz
    /// "OK"/"Yes" yerine eylem adlandırılır (brief 3 "Uygulama Metin Dili").
    var primaryActionTitle: String {
        switch self {
        case .welcome: return "Get Started"
        case .appearance: return "Continue"
        case .finish: return "Open Termora"
        }
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

/// Ekran 2'de yapılan seçimler. Ayarlara yalnızca akış bittiğinde yazılır, böylece
/// kullanıcı ekranlar arasında gezerken açık terminal her tuşta yeniden boyanmaz.
struct OnboardingSelections: Equatable {
    /// Her zaman somut bir yol; algılanan shell önceden seçilidir.
    var shellPath: String
    /// `nil` = sistem monospace fontu (Ayarlar ekranıyla aynı sözleşme).
    var fontName: String?
    var fontSize: Double
    var themeID: String
    /// Kullanıcı hesabının login shell'i; "System default" ayarını korumak için saklanır.
    var detectedShellPath: String

    init(settings: AppSettings, detectedShellPath: String) {
        self.shellPath = settings.defaultShellPath ?? detectedShellPath
        self.fontName = settings.fontName
        self.fontSize = settings.fontSize
        self.themeID = settings.themeID
        self.detectedShellPath = detectedShellPath
    }

    /// Seçimleri ayarların üzerine yazar; onboarding'in ilgilenmediği alanlara dokunmaz.
    func applied(to settings: AppSettings) -> AppSettings {
        var updated = settings
        // Algılanan shell seçili bırakıldıysa ayar "System default" (nil) kalır: aksi hâlde
        // kullanıcı login shell'ini değiştirdiğinde Termora eski yola sabitlenmiş olurdu.
        updated.defaultShellPath = shellPath == detectedShellPath ? nil : shellPath
        updated.fontName = fontName
        updated.fontSize = SettingsLimits.clampFontSize(fontSize)
        updated.themeID = themeID
        return updated
    }
}

/// İlk açılış akışının saf durumu: hangi ekrandayız, ileri/geri, tamamlanma.
/// SwiftUI görünümü yalnızca bunu çizer.
@MainActor
@Observable
final class OnboardingState {
    private(set) var step: OnboardingStep = .welcome
    var selections: OnboardingSelections
    /// Akış kapandı: pencere kapatılabilir. Tamamlama ve atlama aynı sonucu verir.
    private(set) var isFinished = false

    init(settings: AppSettings, detectedShellPath: String) {
        self.selections = OnboardingSelections(settings: settings, detectedShellPath: detectedShellPath)
    }

    convenience init(settings: AppSettings) {
        self.init(settings: settings, detectedShellPath: ShellService.defaultShellPath())
    }

    var canGoBack: Bool { step.previous != nil }
    var primaryActionTitle: String { step.primaryActionTitle }

    /// Son ekranda akışı bitirir, öncesinde bir sonraki ekrana geçer.
    func primaryAction(writingTo store: SettingsStore) {
        if let next = step.next {
            step = next
        } else {
            finish(writingTo: store)
        }
    }

    func goBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    /// Kullanıcı akışı atladı. Brief 2 "Onboarding": atlanabilir olmalı — atlama da
    /// tamamlanmadır, akış bir daha gösterilmez. O ana kadar yapılan seçimler korunur.
    func skip(writingTo store: SettingsStore) {
        finish(writingTo: store)
    }

    func finish(writingTo store: SettingsStore) {
        var updated = selections.applied(to: store.settings)
        updated.hasCompletedOnboarding = true
        store.settings = updated
        isFinished = true
    }
}

/// Ekran 2'deki temsili terminal çıktısı.
///
/// Gerçek bir shell başlatılmaz: onboarding için ikinci bir PTY açmak akışı yavaşlatır
/// ve pencere erken kapatılırsa süreç sızdırır. Örnek çıktı seçilen tema ve fontla
/// boyandığı için önizleme yine "canlı"dır — tema/font değişimi anında görünür.
enum OnboardingPreview {

    /// Bir metin parçasının rengi.
    enum Ink: Equatable {
        /// Temanın normal metin rengi.
        case foreground
        /// Temanın 16 renkli ANSI tablosundaki indeks (0-15).
        case ansi(Int)
    }

    struct Segment: Equatable {
        var text: String
        var ink: Ink
    }

    struct Line: Equatable, Identifiable {
        var id: Int
        var segments: [Segment]
    }

    /// Yalnızca ASCII: Nerd Font kurulu olmayan makinede kutu karakteri görünmesin.
    static let lines: [Line] = [
        Line(id: 0, segments: [
            .init(text: "user@termora", ink: .ansi(4)),
            .init(text: " ~/projects/termora", ink: .ansi(6)),
            .init(text: " (main)", ink: .ansi(3)),
        ]),
        Line(id: 1, segments: [
            .init(text: "$ ", ink: .ansi(2)),
            .init(text: "swift build", ink: .foreground),
        ]),
        Line(id: 2, segments: [
            .init(text: "Compiling Termora (18 sources)", ink: .ansi(8)),
        ]),
        Line(id: 3, segments: [
            .init(text: "Build complete", ink: .ansi(2)),
            .init(text: " in 2.31s", ink: .ansi(8)),
        ]),
        Line(id: 4, segments: [
            .init(text: "$ ", ink: .ansi(2)),
        ]),
    ]
}
