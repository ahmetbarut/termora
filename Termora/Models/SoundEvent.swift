import AppKit

/// briefs/3 "Ses Kullanımı"nın saydığı dört olay.
///
/// Hepsi varsayılan KAPALI: brief'in ilk cümlesi *uygulama varsayılan olarak sessiz
/// olmalıdır* diyor. Bir sesin yanlışlıkla açık gelmesi, kullanıcının istemediği bir
/// anda makinesinin ses çıkarması demektir.
enum SoundEvent: String, CaseIterable, Identifiable, Sendable {
    case bell
    case longCommand
    case sshDisconnected
    case criticalError

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bell: "Terminal bell"
        case .longCommand: "Long command finished"
        case .sshDisconnected: "SSH disconnected"
        case .criticalError: "Critical error"
        }
    }

    var explanation: String {
        switch self {
        case .bell: "When a program rings the terminal bell."
        case .longCommand: "When a command that ran longer than your notification threshold ends."
        case .sshDisconnected: "When an SSH connection drops."
        case .criticalError: "When Termora cannot recover from something."
        }
    }

    /// macOS'un kendi sesleri kullanılır: uygulamayla ses dosyası taşımak, sistem ses
    /// temasına uymayan ve kullanıcının tanımadığı bir ses çıkarmak olurdu.
    var systemSoundName: String {
        switch self {
        case .bell: "Tink"
        case .longCommand: "Glass"
        case .sshDisconnected: "Basso"
        case .criticalError: "Funk"
        }
    }
}

/// Sesleri çalan tek yer.
///
/// Ayar kapalıyken HİÇBİR ses çalınmaz ve `NSSound` bile kurulmaz — kapalı bir özelliğin
/// hiçbir yan etkisi olmamalı.
@MainActor
enum SoundPlayer {
    static func play(_ event: SoundEvent, settings: AppSettings) {
        guard settings.isSoundEnabled(event) else { return }
        NSSound(named: event.systemSoundName)?.play()
    }
}
