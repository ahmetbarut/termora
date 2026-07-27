import Testing
@testable import Termora

@Suite("ExitStatus")
struct ExitStatusTests {

    @Test("normal cikis: raw 0 -> exitCode 0, signal nil")
    func normalExitZero() {
        let status = ExitStatus(rawStatus: 0)
        #expect(status.exitCode == 0)
        #expect(status.signal == nil)
    }

    @Test("normal cikis: raw 256 -> exitCode 1 (WEXITSTATUS)")
    func normalExitOne() {
        let status = ExitStatus(rawStatus: 256)
        #expect(status.exitCode == 1)
        #expect(status.signal == nil)
    }

    @Test("sinyalli cikis: raw 15 -> signal 15 (SIGTERM), exitCode nil")
    func terminatedBySigterm() {
        let status = ExitStatus(rawStatus: 15)
        #expect(status.exitCode == nil)
        #expect(status.signal == 15)
    }

    @Test("sinyalli cikis: raw 9 -> signal 9 (SIGKILL)")
    func terminatedBySigkill() {
        let status = ExitStatus(rawStatus: 9)
        #expect(status.exitCode == nil)
        #expect(status.signal == 9)
    }

    @Test("durdurulmus surec: raw 0x7f -> ikisi de nil")
    func stoppedProcess() {
        let status = ExitStatus(rawStatus: 0x7f)
        #expect(status.exitCode == nil)
        #expect(status.signal == nil)
    }

    @Test("localizedSummary metinleri")
    func summaries() {
        #expect(ExitStatus(rawStatus: 0).localizedSummary == "çıkış kodu 0")
        #expect(ExitStatus(rawStatus: 256).localizedSummary == "çıkış kodu 1")
        #expect(ExitStatus(rawStatus: 15).localizedSummary == "SIGTERM ile sonlandı")
        #expect(ExitStatus(rawStatus: 9).localizedSummary == "SIGKILL ile sonlandı")
        #expect(ExitStatus(rawStatus: 28).localizedSummary == "sinyal 28 ile sonlandı")
        #expect(ExitStatus(rawStatus: 0x7f).localizedSummary == "bilinmeyen durum (raw: 127)")
    }

    @Test("Equatable rawStatus uzerinden")
    func equatable() {
        #expect(ExitStatus(rawStatus: 256) == ExitStatus(rawStatus: 256))
        #expect(ExitStatus(rawStatus: 256) != ExitStatus(rawStatus: 0))
    }
}
