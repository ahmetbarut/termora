import Foundation

/// Durum çubuğunda yol gösterimi: ev dizini `~` ile kısaltılır.
enum PathDisplay {
    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        var normalizedHome = home
        while normalizedHome.count > 1, normalizedHome.hasSuffix("/") {
            normalizedHome.removeLast()
        }
        if path == normalizedHome { return "~" }
        guard path.hasPrefix(normalizedHome + "/") else { return path }
        return "~" + path.dropFirst(normalizedHome.count)
    }
}
