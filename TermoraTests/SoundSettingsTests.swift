import AppKit
import Foundation
import Testing
@testable import Termora

/// briefs/3 "Ses Kullanımı": *Uygulama varsayılan olarak sessiz olmalıdır.*
///
/// Buradaki ilk ve en önemli test o cümledir. Bir ses ayarının yanlışlıkla açık gelmesi,
/// kullanıcının istemediği bir anda makinesinin ses çıkarması demektir.
@Suite("Ses ayarları")
struct SoundSettingsTests {

    @Test func theAppIsSilentOutOfTheBox() {
        let settings = AppSettings()
        for event in SoundEvent.allCases {
            #expect(settings.isSoundEnabled(event) == false, "\(event) varsayılan açık gelmemeli")
        }
    }

    /// briefs/3 dört ses sayıyor ve *her ses ayrı ayrı kapatılabilmelidir* diyor.
    @Test func theBriefsFourSoundsAreAllHere() {
        #expect(SoundEvent.allCases.map(\.title) == [
            "Terminal bell", "Long command finished", "SSH disconnected", "Critical error",
        ])
    }

    @Test func eachSoundIsSwitchedIndependently() {
        var settings = AppSettings()
        settings.setSoundEnabled(.bell, true)

        #expect(settings.isSoundEnabled(.bell))
        #expect(settings.isSoundEnabled(.longCommand) == false)
        #expect(settings.isSoundEnabled(.sshDisconnected) == false)
        #expect(settings.isSoundEnabled(.criticalError) == false)
    }

    @Test func everySoundNamesASystemSoundThatExists() {
        for event in SoundEvent.allCases {
            #expect(NSSound(named: event.systemSoundName) != nil,
                    "\(event.systemSoundName) macOS'ta yok")
        }
    }

    /// Görsel bell, sesi kapalı tutan kullanıcı için: briefs/3 sessizliği varsayılan
    /// yapıyor ama bell'in bir karşılığı olmalı.
    @Test func theVisualBellIsSeparateFromTheAudibleOne() {
        var settings = AppSettings()
        #expect(settings.usesVisualBell == false)

        settings.usesVisualBell = true
        #expect(settings.usesVisualBell)
        // Görsel bell açmak sesi AÇMAZ.
        #expect(settings.isSoundEnabled(.bell) == false)
    }

    /// Ayar dosyasında kayıt yoksa ses KAPALI kabul edilir: eksik veri asla sesi
    /// kendiliğinden açmamalı.
    @Test func amissingRecordMeansSilence() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        for event in SoundEvent.allCases {
            #expect(decoded.isSoundEnabled(event) == false)
        }
    }
}
