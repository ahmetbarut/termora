import Foundation

/// Terminal alt sureci icin ortam degiskenlerini kurar.
/// SwiftTerm'un `Terminal.getEnvironmentVariables`'i KULLANILMAZ:
/// LC_TYPE yazim hatasi vardir (LC_CTYPE aynalanmaz) ve PATH/SHELL eklenmez.
/// PATH bilincli olarak eklenmez — her oturum login shell olarak baslar,
/// PATH'i shell'in kendi baslangic dosyalari kurar.
enum EnvironmentBuilder {

    /// Kolaylik sarmalayici: base = gercek surec ortami.
    static func environment(extra: [String: String] = [:]) -> [String] {
        environment(base: ProcessInfo.processInfo.environment, extra: extra)
    }

    /// Test dikisli saf cekirdek. Cikti "KEY=VALUE" dizisidir (deterministik siralama).
    static func environment(base: [String: String], extra: [String: String] = [:]) -> [String] {
        var env: [String: String] = [:]
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = base["LANG"] ?? "en_US.UTF-8"
        if let lcCtype = base["LC_CTYPE"] {
            env["LC_CTYPE"] = lcCtype
        }
        for key in ["HOME", "USER", "LOGNAME"] {
            if let value = base[key] {
                env[key] = value
            }
        }
        env["TERM_PROGRAM"] = "Termora"
        env["TERM_PROGRAM_VERSION"] = appVersion
        for (key, value) in extra {
            env[key] = value
        }
        return env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
