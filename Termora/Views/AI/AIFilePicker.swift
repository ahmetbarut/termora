import AppKit
import UniformTypeIdentifiers

/// Dosya ekleme için standart macOS açma paneli (briefs/2 "Kullanıcının açıkça eklediği
/// dosyalar").
///
/// Ayrı bir tip: `AIPanelModel` bunu bir kapanış dikişi üzerinden çağırır, böylece testler
/// gerçek bir panel açmaz. Panel yalnız kullanıcı DÜĞMEYE BASINCA açılır; Termora kendi
/// başına hiçbir dosyaya bakmaz.
enum AIFilePicker {

    @MainActor
    static func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        // Klasör seçmek, içindeki her şeyi göndermeye davet olurdu; kullanıcı hangi
        // dosyanın gittiğini tek tek görmeli.
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Attach files to send with your next question."
        panel.prompt = "Attach"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
