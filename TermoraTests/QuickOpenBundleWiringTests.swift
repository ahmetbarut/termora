import AppKit
import Foundation
import Testing
@testable import Termora

/// Hızlı açmanın PAKET tarafı: `termora://` şeması ve Finder servisi Info.plist'te
/// tanımlıdır, kodun beklediği adlarla eşleşmelidir.
///
/// Bu iki taraf ayrı dosyalarda yazıldığı için sessizce kopabilir: plist'teki bir yazım
/// hatası şemayı ölü bırakır, servisin `NSMessage` adı yöntemin adından saparsa menü
/// girdisi hiçbir şey yapmaz. Testler bu bağı derleme değil, ÇALIŞAN paket üzerinden
/// kontrol eder (`Bundle.main` burada Termora.app'tir).
@MainActor
@Suite("Hızlı açma paket tanımları")
struct QuickOpenBundleWiringTests {

    @Test func theAppDeclaresTheTermoraURLScheme() throws {
        let types = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        #expect(schemes.contains(TermoraURL.scheme))
    }

    /// Taban Info.plist vermek Xcode'un ÜRETTİĞİ anahtarları kapatmamalı; kapatsaydı
    /// paketin kimliği ve sürümü kaybolurdu.
    @Test func theGeneratedInfoPlistKeysSurviveTheBaseFile() {
        #expect(Bundle.main.bundleIdentifier == "com.ahmetbarut.Termora")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") != nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") != nil)
    }

    @Test func theFinderServiceIsDeclaredForFoldersOnly() throws {
        let services = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]])
        let entry = try #require(
            services.first { $0["NSMessage"] as? String == FinderService.messageName })

        #expect((entry["NSMenuItem"] as? [String: String])?["default"]
                == FinderService.menuItemTitle)
        // Yalnız klasör: bir DOSYA seçiliyken girdi menüde hiç görünmemeli.
        #expect(entry["NSSendFileTypes"] as? [String] == ["public.folder"])
        // Genel pano türü istenmez; istenseydi metin seçimlerinde de çıkardı.
        #expect(entry.keys.contains("NSSendTypes") == false)
        // Servis YALNIZ gönderir; Termora servis menüsüne bir dönüş değeri vaat etmez.
        #expect(entry.keys.contains("NSReturnTypes") == false)
    }

    /// Info.plist'teki `NSMessage` gerçekten var olan bir yönteme mi bakıyor?
    @Test func theDeclaredServiceMessageIsImplemented() {
        let selector = NSSelectorFromString("\(FinderService.messageName):userData:error:")

        #expect(TermoraServicesProvider.instancesRespond(to: selector))
    }
}
