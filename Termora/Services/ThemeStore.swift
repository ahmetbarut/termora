import Foundation
import os

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

    let themes: [Theme]

    init(bundle: Bundle = .main) {
        // File-synchronized groups may flatten resources into the bundle root,
        // so probe the expected subdirectories first and fall back to the root.
        var urls: [URL] = []
        for subdirectory: String? in ["Themes", "Resources/Themes", nil] {
            urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []
            if !urls.isEmpty { break }
        }
        let decoder = JSONDecoder()
        let loaded = urls.compactMap { url -> Theme? in
            guard let data = try? Data(contentsOf: url),
                  let theme = try? decoder.decode(Theme.self, from: data),
                  theme.ansi.count == 16 else {
                Self.logger.error("Skipping theme resource that failed to load: \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            return theme
        }
        themes = loaded.isEmpty
            ? [Self.fallback]
            : loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func theme(id: String) -> Theme {
        themes.first { $0.id == id } ?? Self.fallback
    }
}
