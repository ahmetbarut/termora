import Testing
@testable import Termora

/// brief 3 "Animasyonlar" bölümünün saf mantığı: süreler brief'in 120–180 ms penceresinde
/// kalmalı ve sistemin "Reduce Motion" tercihi açıkken hiçbir animasyon üretilmemeli.
@MainActor
@Suite("Hareket kuralları")
struct MotionTests {

    @Test func briefWindowIsExactlyOneHundredTwentyToOneHundredEightyMilliseconds() {
        #expect(Motion.durationRange.lowerBound == 0.120)
        #expect(Motion.durationRange.upperBound == 0.180)
    }

    @Test func everySpeedStaysInsideTheBriefWindow() {
        for speed in Motion.Speed.allCases {
            #expect(Motion.durationRange.contains(speed.duration),
                    "brief 3 penceresinin dışına çıkan hız: \(speed)")
        }
    }

    @Test func thereAreThreeDistinctSpeedsOrderedFromShortestToLongest() {
        #expect(Motion.Speed.allCases.count == 3)
        let durations = Motion.Speed.allCases.map(\.duration)
        #expect(Set(durations).count == durations.count)
        #expect(Motion.Speed.hover.duration < Motion.Speed.selection.duration)
        #expect(Motion.Speed.selection.duration < Motion.Speed.panel.duration)
    }

    /// Kritik davranış: Reduce Motion açıkken süre YOKTUR — değişim tek karede biter.
    /// nil dönmek "0 sn animasyon" kurmaktan farklıdır; SwiftUI hiç geçiş kurmaz.
    @Test func reduceMotionRemovesEveryDurationAndAnimation() {
        for speed in Motion.Speed.allCases {
            #expect(Motion.duration(speed, reduceMotion: true) == nil,
                    "Reduce Motion açıkken süre üretildi: \(speed)")
            #expect(Motion.animation(speed, reduceMotion: true) == nil,
                    "Reduce Motion açıkken animasyon üretildi: \(speed)")
        }
    }

    @Test func normalMotionKeepsTheDeclaredDuration() {
        for speed in Motion.Speed.allCases {
            #expect(Motion.duration(speed, reduceMotion: false) == speed.duration)
            #expect(Motion.animation(speed, reduceMotion: false) != nil)
        }
    }

    /// Hızların rolleri brief'teki kullanım alanlarına bağlıdır; isimler kaymasın.
    @Test func speedsCoverTheBriefsAnimatableSurfaces() {
        #expect(Motion.Speed.hover.duration == 0.120)
        #expect(Motion.Speed.selection.duration == 0.150)
        #expect(Motion.Speed.panel.duration == 0.180)
    }
}
