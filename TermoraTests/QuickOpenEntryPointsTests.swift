import AppKit
import Foundation
import Testing
@testable import Termora

/// Hızlı açmanın DIŞ kapıları (briefs/2): `termora://open` ve Finder ▸ Services.
///
/// Ayrıştırıcının kendi testleri `TermoraURLTests`'te; burada test edilen şey kapıların
/// o ayrıştırıcıya BAĞLI olduğudur — yani reddedilen bir istek pencereye hiç ulaşmaz.
@MainActor
@Suite("Hızlı açmanın dış kapıları")
struct QuickOpenEntryPointsTests {

    private struct Subject {
        let services: AppServices
        let folder: String
        let file: String
    }

    /// Gerçek bir klasör kurar: doğrulama diske bakar, sahte yol kabul edilmez.
    private func makeSubject() throws -> Subject {
        let suiteName = "QuickOpenEntry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quick-open-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("pinro")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)

        return Subject(services: AppServices(defaults: defaults),
                       folder: folder.path,
                       file: file.path)
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    /// Yol içinde boşluk olabilir; kodlanmış hâli kurulmalı.
    private func encoded(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
    }

    // MARK: - URL şeması

    @Test func aValidURLParksAFolderOpenRequest() throws {
        let subject = try makeSubject()

        subject.services.handleIncomingURL(try url("termora://open?path=\(encoded(subject.folder))"))

        #expect(subject.services.folderOpenRequest?.paths == [subject.folder])
    }

    /// GÜVENLİK: komut taşıyan bir URL pencereye HİÇ ULAŞMAZ — istek park bile edilmez.
    @Test func aURLCarryingACommandNeverReachesAWindow() throws {
        let subject = try makeSubject()

        subject.services.handleIncomingURL(
            try url("termora://open?path=\(encoded(subject.folder))&command=rm%20-rf%20~"))

        #expect(subject.services.folderOpenRequest == nil)
    }

    @Test func aFilePathIsNotParked() throws {
        let subject = try makeSubject()

        subject.services.handleIncomingURL(try url("termora://open?path=\(encoded(subject.file))"))

        #expect(subject.services.folderOpenRequest == nil)
    }

    @Test func anUnknownActionIsNotParked() throws {
        let subject = try makeSubject()

        subject.services.handleIncomingURL(try url("termora://exec?path=\(encoded(subject.folder))"))

        #expect(subject.services.folderOpenRequest == nil)
    }

    /// Aynı klasör arka arkaya iki kez istendiğinde ikinci istek de görülmeli: pencere
    /// `id` değişimini izliyor, aynı `id` ikinci sekmeyi hiç açmazdı.
    @Test func askingTwiceForTheSameFolderProducesTwoDistinctRequests() throws {
        let subject = try makeSubject()
        let link = try url("termora://open?path=\(encoded(subject.folder))")

        subject.services.handleIncomingURL(link)
        let first = subject.services.folderOpenRequest
        subject.services.handleIncomingURL(link)

        #expect(first != nil)
        #expect(subject.services.folderOpenRequest != first)
    }

    @Test func anEmptyRequestIsIgnored() throws {
        let subject = try makeSubject()

        subject.services.requestOpenFolder(paths: [])

        #expect(subject.services.folderOpenRequest == nil)
    }

    // MARK: - Finder ▸ Services ▸ Open in Termora

    private func pasteboard(with urls: [URL]) throws -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("QuickOpenTest.\(UUID().uuidString)"))
        board.clearContents()
        #expect(board.writeObjects(urls as [NSURL]))
        return board
    }

    @Test func theServiceParksTheSelectedFolders() throws {
        let subject = try makeSubject()
        let provider = TermoraServicesProvider(services: subject.services)
        let board = try pasteboard(with: [URL(fileURLWithPath: subject.folder)])
        var message: NSString?

        provider.openFolderInTermora(board, userData: nil, error: &message)

        #expect(subject.services.folderOpenRequest?.paths == [subject.folder])
        #expect(message == nil)
    }

    /// Bir DOSYA seçiliyken servis hiçbir şey açmaz ve nedenini söyler.
    @Test func theServiceRefusesAFileAndExplainsWhy() throws {
        let subject = try makeSubject()
        let provider = TermoraServicesProvider(services: subject.services)
        let board = try pasteboard(with: [URL(fileURLWithPath: subject.file)])
        var message: NSString?

        provider.openFolderInTermora(board, userData: nil, error: &message)

        #expect(subject.services.folderOpenRequest == nil)
        #expect(message == "Select a folder to open in Termora.")
    }
}
