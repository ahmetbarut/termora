import Foundation
import Testing
@testable import Termora

/// briefs/2 "Hata Raporlama".
///
/// Brief bir izin listesi değil bir YASAK listesi veriyor: terminal çıktısı, yazılan
/// komutlar, dosya içerikleri, ortam değişkenleri, API anahtarları ve SSH bilgileri
/// raporda BULUNMAMALI. Bu paket o yasağı sınar — bir alan sızarsa test kırmızıya döner.
@Suite("Hata raporlama")
struct CrashReportTests {

    @Test func reportingIsOffUntilTheUserTurnsItOn() {
        #expect(AppSettings().sendsCrashReports == false)
    }

    /// Eksik kayıt KAPALI sayılır: eksik veri asla raporlamayı kendiliğinden açmamalı.
    @Test func amissingRecordMeansDisabled() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.sendsCrashReports == false)
    }

    @Test func areportCarriesOnlyTheFourFieldsTheBriefAllows() {
        let report = CrashReport(
            appVersion: "1.2.0",
            buildNumber: "42",
            systemVersion: "macOS 15.0",
            architecture: "arm64",
            stackTrace: "0  Termora  0x1  main + 1"
        )

        let text = report.text
        #expect(text.contains("1.2.0"))
        #expect(text.contains("macOS 15.0"))
        #expect(text.contains("arm64"))
        #expect(text.contains("main + 1"))
    }

    /// Yasak listesinin kendisi. Rapor metni bu alanların HİÇBİRİNİ taşımaz — çünkü
    /// tip onları hiç kabul etmiyor.
    @Test func theReportTypeHasNowhereToPutForbiddenData() {
        let mirror = Mirror(reflecting: CrashReport(
            appVersion: "1", buildNumber: "1", systemVersion: "1",
            architecture: "1", stackTrace: "1"
        ))
        let fields = Set(mirror.children.compactMap(\.label))

        #expect(fields == ["appVersion", "buildNumber", "systemVersion",
                           "architecture", "stackTrace"])
        // Brief'in yasakladıkları için alan YOK: sızmanın yapısal olarak yolu kapalı.
        for forbidden in ["output", "command", "environment", "apiKey", "sshHost", "fileContents"] {
            #expect(fields.contains(forbidden) == false, "\(forbidden) alanı olmamalı")
        }
    }

    /// Stack trace'te dosya YOLU görünebilir; kullanıcı adı da onunla sızar. Ev dizini
    /// yolları kısaltılır.
    @Test func homeDirectoryPathsAreRedactedFromTheStackTrace() {
        let raw = "0 Termora 0x1 /Users/ahmetbarut/Projects/secret/main.swift:12"
        let report = CrashReport(appVersion: "1", buildNumber: "1", systemVersion: "1",
                                 architecture: "1", stackTrace: raw)

        #expect(report.text.contains("/Users/ahmetbarut") == false)
        #expect(report.text.contains("~/"))
    }

    /// Kullanıcı göndermeden ÖNCE raporun tamamını görebilmeli (briefs/2: gönderilecek
    /// içerik incelenebilmeli). Metin bunun için var — ayrı bir "önizleme" biçimi
    /// olsaydı gönderilenle gösterilen ayrışabilirdi.
    @Test func whatTheUserSeesIsExactlyWhatWouldBeSent() {
        let report = CrashReport(appVersion: "9", buildNumber: "9", systemVersion: "9",
                                 architecture: "9", stackTrace: "trace")
        #expect(report.text == report.previewText)
    }
}
