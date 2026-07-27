import Foundation

/// `waitpid`'den gelen ham status degerini ayristirir.
/// Darwin'in WIFEXITED/WEXITSTATUS/WIFSIGNALED/WTERMSIG makrolari C makrosu oldugundan
/// Swift'e kopru kurulmaz; formuller elle uygulanir:
///   WIFEXITED(s)   = (s & 0x7f) == 0
///   WEXITSTATUS(s) = (s >> 8) & 0xff
///   WIFSIGNALED(s) = ((s & 0x7f) != 0x7f) && ((s & 0x7f) != 0)
///   WTERMSIG(s)    = s & 0x7f
struct ExitStatus: Equatable {
    let rawStatus: Int32

    /// WIFEXITED ise WEXITSTATUS, degilse nil.
    var exitCode: Int32? {
        guard (rawStatus & 0x7f) == 0 else { return nil }
        return (rawStatus >> 8) & 0xff
    }

    /// WIFSIGNALED ise WTERMSIG, degilse nil.
    var signal: Int32? {
        let low = rawStatus & 0x7f
        guard low != 0x7f, low != 0 else { return nil }
        return low
    }

    var localizedSummary: String {
        if let code = exitCode {
            return "çıkış kodu \(code)"
        }
        if let sig = signal {
            if let name = Self.signalNames[sig] {
                return "\(name) ile sonlandı"
            }
            return "sinyal \(sig) ile sonlandı"
        }
        return "bilinmeyen durum (raw: \(rawStatus))"
    }

    private static let signalNames: [Int32: String] = [
        SIGHUP: "SIGHUP", SIGINT: "SIGINT", SIGQUIT: "SIGQUIT",
        SIGILL: "SIGILL", SIGTRAP: "SIGTRAP", SIGABRT: "SIGABRT",
        SIGFPE: "SIGFPE", SIGKILL: "SIGKILL", SIGBUS: "SIGBUS",
        SIGSEGV: "SIGSEGV", SIGPIPE: "SIGPIPE", SIGALRM: "SIGALRM",
        SIGTERM: "SIGTERM",
    ]
}
