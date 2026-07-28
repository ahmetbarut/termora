import Foundation
import Observation
import os

/// İçe aktarılan bir dosyanın kütüphaneye nasıl yerleştiği.
///
/// Çakışma SESSİZ çözülmez: kullanıcı hangi temanın değiştiğini ya da neden başka bir
/// kimlik aldığını `ThemeImportResult.statusMessage` ile görür.
enum ThemeImportDisposition: Equatable {
    /// Kimlik boştaydı, tema listeye eklendi.
    case added
    /// Aynı kimlikli KULLANICI teması vardı; dosya onun kaynağı sayılır ve yerine yazılır.
    case replacedUserTheme
    /// Kimlik bir PAKET temasına aitti. Paket temaları salt okunurdur, bu yüzden içe
    /// aktarılan tema yeni bir kimlik alır.
    case addedWithGeneratedID(requestedID: String)
}

/// Bir içe aktarmanın sonucu ve kullanıcıya söylenecek cümle.
struct ThemeImportResult: Equatable {
    let theme: Theme
    let disposition: ThemeImportDisposition

    var statusMessage: String {
        switch disposition {
        case .added:
            return "Imported “\(theme.name)”."
        case .replacedUserTheme:
            return "Updated “\(theme.name)” from the imported file."
        case .addedWithGeneratedID(let requestedID):
            return "Imported “\(theme.name)” as “\(theme.id)”. "
                + "“\(requestedID)” belongs to a built-in theme, which Termora keeps read-only."
        }
    }
}

/// Kimlik çakışmasının SAF çözümü: disk yok, panel yok, yalnız girdi ve çıktı.
enum ThemeImportResolver {

    struct Resolution: Equatable {
        let theme: Theme
        let disposition: ThemeImportDisposition
        /// Çözümden sonraki kullanıcı teması listesi.
        let userThemes: [Theme]
    }

    static func resolve(_ theme: Theme,
                        builtInIDs: Set<String>,
                        userThemes: [Theme]) -> Resolution {
        if builtInIDs.contains(theme.id) {
            let taken = builtInIDs.union(userThemes.map(\.id))
            var renamed = theme
            var suffix = 2
            while taken.contains("\(theme.id)-\(suffix)") {
                suffix += 1
            }
            renamed.id = "\(theme.id)-\(suffix)"
            return Resolution(theme: renamed,
                              disposition: .addedWithGeneratedID(requestedID: theme.id),
                              userThemes: userThemes + [renamed])
        }
        if let index = userThemes.firstIndex(where: { $0.id == theme.id }) {
            var updated = userThemes
            updated[index] = theme
            return Resolution(theme: theme, disposition: .replacedUserTheme, userThemes: updated)
        }
        return Resolution(theme: theme, disposition: .added, userThemes: userThemes + [theme])
    }
}

/// Uygulamayla gelen temalar ve kullanıcının içe aktardıkları.
///
/// İki kaynak AYRI yaşar: paket temaları salt okunurdur ve uygulama güncellendiğinde
/// değişir; kullanıcı temaları Application Support altındaki klasörde durur ve yalnız
/// kullanıcı onları ekler/siler. `themes` ikisinin ada göre sıralanmış birleşimidir.
@Observable
final class ThemeStore {
    /// Embedded copy of termora-dark; used when a theme ID is unknown or no resources load.
    static let fallback = Theme(
        id: "termora-dark",
        name: "Termora Dark",
        background: "#16181D",
        foreground: "#EAEAEA",
        cursor: "#AEAFAD",
        selection: "#264F78",
        ansi: [
            "#000000", "#CD3131", "#0DBC79", "#E5E510",
            "#2472C8", "#BC3FBC", "#11A8CD", "#E5E5E5",
            "#666666", "#F14C4C", "#23D18B", "#F5F543",
            "#3B8EEA", "#D670D6", "#29B8DB", "#FFFFFF",
        ])

    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "ThemeStore")

    /// Kullanıcı temalarının yaşadığı klasör. Uygulama paketiyle ilgisi yoktur, bu yüzden
    /// uygulama güncellendiğinde kullanıcının temaları yerinde kalır.
    static var defaultUserThemesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Termora/Themes", isDirectory: true)
    }

    let userThemesDirectory: URL

    /// Uygulamayla gelenler. Salt okunur: içe aktarma onları ezmez, silme dokunmaz.
    private(set) var builtInThemes: [Theme]
    /// Kullanıcının içe aktardıkları.
    private(set) var userThemes: [Theme]

    /// Arayüzün gördüğü tek liste. Kimlikler benzersizdir; Picker `id`'yi tag olarak
    /// kullandığı için tekrar eden kimlik seçimi bozardı.
    var themes: [Theme] {
        Self.sortedByName(builtInThemes + userThemes)
    }

    init(bundle: Bundle = .main, userThemesDirectory: URL? = nil) {
        self.userThemesDirectory = userThemesDirectory ?? Self.defaultUserThemesDirectory
        let bundled = Self.loadBundledThemes(from: bundle)
        let builtIn = bundled.isEmpty ? [Self.fallback] : Self.sortedByName(bundled)
        builtInThemes = builtIn
        userThemes = Self.loadUserThemes(in: userThemesDirectory ?? Self.defaultUserThemesDirectory,
                                         reservedIDs: Set(builtIn.map(\.id)))
    }

    func theme(id: String) -> Theme {
        // Kimlikler iki kaynak arasında benzersiz olduğu için sıralı listeyi kurmadan aranır;
        // bu çağrı her terminal oturumu açılışında yapılıyor.
        builtInThemes.first { $0.id == id } ?? userThemes.first { $0.id == id } ?? Self.fallback
    }

    func isBuiltIn(id: String) -> Bool {
        builtInThemes.contains { $0.id == id }
    }

    // MARK: - İçe / dışa aktarma

    /// Dosyayı doğrular, çakışmayı çözer ve kullanıcı kütüphanesine yazar.
    /// Başarısızlık `ThemeFileError` olarak DIŞARI çıkar; çağıran onu kullanıcıya göstermek
    /// zorundadır, çünkü sessiz bir "hiçbir şey olmadı" en kötü sonuçtur.
    @discardableResult
    func importTheme(from url: URL) throws -> ThemeImportResult {
        let fileName = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeFileError(reason: .unreadableFile(error.localizedDescription), fileName: fileName)
        }

        let decoded = try ThemeFile.theme(fromJSON: data, fileName: fileName)
        let resolution = ThemeImportResolver.resolve(decoded,
                                                     builtInIDs: Set(builtInThemes.map(\.id)),
                                                     userThemes: userThemes)
        let destination = userThemesDirectory
            .appendingPathComponent(ThemeFile.suggestedFileName(for: resolution.theme))
        do {
            try FileManager.default.createDirectory(at: userThemesDirectory,
                                                    withIntermediateDirectories: true)
            try ThemeFile.encoded(resolution.theme).write(to: destination, options: .atomic)
        } catch {
            throw ThemeFileError(reason: .couldNotAddToLibrary(error.localizedDescription),
                                 fileName: fileName)
        }
        // Elle klasöre atılmış, aynı kimliği taşıyan başka bir dosya kalırsa tema bir daha
        // yüklendiğinde hangi sürümün kazandığı dosya adı sırasına kalırdı.
        removeUserThemeFiles(id: resolution.theme.id, keeping: destination.lastPathComponent)

        userThemes = Self.sortedByName(resolution.userThemes)
        return ThemeImportResult(theme: resolution.theme, disposition: resolution.disposition)
    }

    /// Temayı dosyaya yazar. Yazılan dosya geri içe aktarılabilir.
    func exportTheme(_ theme: Theme, to url: URL) throws {
        do {
            try ThemeFile.encoded(theme).write(to: url, options: .atomic)
        } catch {
            throw ThemeFileError(reason: .couldNotSave(error.localizedDescription),
                                 fileName: url.lastPathComponent)
        }
    }

    /// Kullanıcı temasını listeden ve diskten kaldırır. Paket temaları için hiçbir şey yapmaz.
    func removeUserTheme(id: String) {
        guard !isBuiltIn(id: id), userThemes.contains(where: { $0.id == id }) else { return }
        removeUserThemeFiles(id: id, keeping: nil)
        userThemes.removeAll { $0.id == id }
    }

    // MARK: - Yükleme

    private static func sortedByName(_ themes: [Theme]) -> [Theme] {
        themes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func loadBundledThemes(from bundle: Bundle) -> [Theme] {
        // File-synchronized groups may flatten resources into the bundle root,
        // so probe the expected subdirectories first and fall back to the root.
        var urls: [URL] = []
        for subdirectory: String? in ["Themes", "Resources/Themes", nil] {
            urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []
            if !urls.isEmpty { break }
        }
        var loaded: [Theme] = []
        var seen = Set<String>()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let theme = decodeTheme(at: url) else { continue }
            guard seen.insert(theme.id).inserted else {
                logger.error("Skipping duplicate bundled theme id: \(theme.id, privacy: .public)")
                continue
            }
            loaded.append(theme)
        }
        return loaded
    }

    private static func loadUserThemes(in directory: URL, reservedIDs: Set<String>) -> [Theme] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            return []
        }
        var loaded: [Theme] = []
        var seen = reservedIDs
        for url in urls.filter({ $0.pathExtension.lowercased() == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let theme = decodeTheme(at: url) else { continue }
            // Paket temasının kimliğini taşıyan elle konmuş dosya listeye ALINMAZ;
            // salt okunur temayı gölgelemesi seçimi belirsizleştirirdi.
            guard seen.insert(theme.id).inserted else {
                logger.error("Skipping user theme with a taken id: \(url.lastPathComponent, privacy: .public)")
                continue
            }
            loaded.append(theme)
        }
        return sortedByName(loaded)
    }

    private static func decodeTheme(at url: URL) -> Theme? {
        do {
            return try ThemeFile.theme(fromJSON: try Data(contentsOf: url),
                                       fileName: url.lastPathComponent)
        } catch {
            logger.error("Skipping theme file that failed to load: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    private func removeUserThemeFiles(id: String, keeping keptFileName: String?) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: userThemesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            return
        }
        for url in urls where url.pathExtension.lowercased() == "json"
            && url.lastPathComponent != keptFileName {
            guard Self.decodeTheme(at: url)?.id == id else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
