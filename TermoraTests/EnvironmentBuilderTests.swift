import Foundation
import Testing
@testable import Termora

@Suite("EnvironmentBuilder")
struct EnvironmentBuilderTests {

    /// "KEY=VALUE" listesini sozluge cevirir (deger icindeki '=' korunur).
    private func dict(_ entries: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            result[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
        }
        return result
    }

    @Test("sabit anahtarlar: TERM, COLORTERM, TERM_PROGRAM")
    func staticKeys() {
        let env = dict(EnvironmentBuilder.environment(base: [:], extra: [:]))
        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["TERM_PROGRAM"] == "Termora")
        #expect(env["TERM_PROGRAM_VERSION"]?.isEmpty == false)
    }

    @Test("LANG: base'de yoksa en_US.UTF-8, varsa aynen")
    func langDefaultAndPassthrough() {
        let missing = dict(EnvironmentBuilder.environment(base: [:], extra: [:]))
        #expect(missing["LANG"] == "en_US.UTF-8")
        let present = dict(EnvironmentBuilder.environment(base: ["LANG": "tr_TR.UTF-8"], extra: [:]))
        #expect(present["LANG"] == "tr_TR.UTF-8")
    }

    @Test("LC_CTYPE yalniz base'de varsa gecer")
    func lcCtypeOnlyWhenPresent() {
        let without = dict(EnvironmentBuilder.environment(base: [:], extra: [:]))
        #expect(without["LC_CTYPE"] == nil)
        let with = dict(EnvironmentBuilder.environment(base: ["LC_CTYPE": "UTF-8"], extra: [:]))
        #expect(with["LC_CTYPE"] == "UTF-8")
    }

    @Test("HOME/USER/LOGNAME base'den aynalanir")
    func identityKeysFromBase() {
        let base = ["HOME": "/Users/test", "USER": "test", "LOGNAME": "test", "PATH": "/usr/bin"]
        let env = dict(EnvironmentBuilder.environment(base: base, extra: [:]))
        #expect(env["HOME"] == "/Users/test")
        #expect(env["USER"] == "test")
        #expect(env["LOGNAME"] == "test")
        #expect(env["PATH"] == nil) // PATH bilincli olarak login shell'e birakilir
    }

    @Test("extra en son uygulanir ve override eder")
    func extraOverrides() {
        let env = dict(EnvironmentBuilder.environment(
            base: ["LANG": "tr_TR.UTF-8"],
            extra: ["LANG": "C", "EDITOR": "vim", "TERM": "dumb"]
        ))
        #expect(env["LANG"] == "C")
        #expect(env["EDITOR"] == "vim")
        #expect(env["TERM"] == "dumb")
    }

    @Test("cikti bicimi KEY=VALUE ve anahtarlar tekil")
    func outputFormat() {
        let entries = EnvironmentBuilder.environment(base: ["HOME": "/Users/test"], extra: [:])
        for entry in entries {
            #expect(entry.contains("="), "beklenen KEY=VALUE, gelen: \(entry)")
        }
        let keys = entries.map { $0.split(separator: "=", maxSplits: 1)[0] }
        #expect(Set(keys).count == keys.count)
    }

    @Test("kolaylik sarmalayici gercek ortami kullanir")
    func convenienceUsesProcessEnvironment() {
        let env = dict(EnvironmentBuilder.environment())
        #expect(env["HOME"] == ProcessInfo.processInfo.environment["HOME"])
        #expect(env["TERM_PROGRAM"] == "Termora")
    }
}
