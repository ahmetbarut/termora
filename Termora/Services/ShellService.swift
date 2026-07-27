import Darwin
import Foundation

/// Secilebilir bir shell: path kimliktir, displayName son yol bilesenidir.
struct ShellInfo: Equatable, Identifiable {
    var id: String { path }
    let path: String
    let displayName: String
}

enum ShellService {

    /// Kullanicinin gercek varsayilan shell'i. GUI uygulamada SHELL env bayat
    /// olabileceginden kullanici veritabanindan (`getpwuid_r().pw_shell`) okunur;
    /// bos/erisilemezse /bin/zsh'e duser.
    ///
    /// `pw_shell` `buffer`'in icine isaret eder ve `&buffer` ile uretilen isaretci
    /// YALNIZ cagri suresince gecerlidir; bu yuzden String kopyasi
    /// `withUnsafeMutableBufferPointer` blogunun ICINDE alinir.
    static func defaultShellPath() -> String {
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>? = nil
        var buffer = [CChar](repeating: 0, count: 4096)
        let shell: String? = buffer.withUnsafeMutableBufferPointer { raw -> String? in
            guard getpwuid_r(getuid(), &pwd, raw.baseAddress, raw.count, &result) == 0,
                  result != nil,
                  let shellPtr = pwd.pw_shell else { return nil }
            let value = String(cString: shellPtr)
            return value.isEmpty ? nil : value
        }
        return shell ?? "/bin/zsh"
    }

    /// Test dikisli saf cekirdek: /etc/shells icerigini parse eder (yorum/bos satir
    /// atlanir, bosluk kirpilir), homebrew adaylarini ekler, isExecutable ile suzer,
    /// sirayi koruyarak tekillestirir.
    static func availableShells(
        etcShellsContents: String?,
        homebrewCandidates: [String],
        isExecutable: (String) -> Bool
    ) -> [ShellInfo] {
        var candidates: [String] = []
        if let contents = etcShellsContents {
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                candidates.append(trimmed)
            }
        }
        candidates.append(contentsOf: homebrewCandidates)

        var seen = Set<String>()
        var shells: [ShellInfo] = []
        for path in candidates {
            guard seen.insert(path).inserted, isExecutable(path) else { continue }
            shells.append(ShellInfo(path: path, displayName: (path as NSString).lastPathComponent))
        }
        return shells
    }

    /// Gercek dosya sisteminden okuyan kolaylik sarmalayici.
    static func availableShells() -> [ShellInfo] {
        let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8)
        return availableShells(
            etcShellsContents: contents,
            homebrewCandidates: ["/opt/homebrew/bin/fish", "/usr/local/bin/fish"],
            isExecutable: { access($0, X_OK) == 0 }
        )
    }

    /// Login shell konvansiyonu: argv[0] = "-" + son bilesen ("/bin/zsh" -> "-zsh").
    /// SwiftTerm `startProcess(execName:)` parametresine verilir.
    static func loginArgv0(forShellPath path: String) -> String {
        "-" + (path as NSString).lastPathComponent
    }
}
