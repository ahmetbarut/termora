//
//  PaneFrameConverterTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@Suite("PaneFrameConverter")
struct PaneFrameConverterTests {

    @Test("SwiftUI üst panel AppKit'te yüksek y'ye taşınır")
    func flipsTopPane() {
        let top = CGRect(x: 0, y: 0, width: 100, height: 80)       // SwiftUI: en üstte
        let converted = PaneFrameConverter.appKitFrame(top, containerHeight: 200)
        #expect(converted == CGRect(x: 0, y: 120, width: 100, height: 80))
    }

    @Test("SwiftUI alt panel AppKit'te y = 0 olur")
    func flipsBottomPane() {
        let bottom = CGRect(x: 0, y: 80, width: 100, height: 120)  // SwiftUI: altta
        let converted = PaneFrameConverter.appKitFrame(bottom, containerHeight: 200)
        #expect(converted == CGRect(x: 0, y: 0, width: 100, height: 120))
    }

    @Test("çevrim kendi tersidir")
    func conversionIsInvolutive() {
        let frame = CGRect(x: 10, y: 30, width: 50, height: 40)
        let once = PaneFrameConverter.appKitFrame(frame, containerHeight: 200)
        let twice = PaneFrameConverter.appKitFrame(once, containerHeight: 200)
        #expect(twice == frame)
    }

    @Test("sözlük çevriminde x ve boyut korunur, dikey sıralama ters döner")
    func convertsDictionary() {
        let topID = UUID(), bottomID = UUID()
        let frames: [UUID: CGRect] = [
            topID: CGRect(x: 0, y: 0, width: 100, height: 80),
            bottomID: CGRect(x: 0, y: 80, width: 100, height: 120)
        ]
        let converted = PaneFrameConverter.appKitFrames(frames, containerHeight: 200)

        #expect(converted.count == 2)
        #expect(converted[topID]?.minX == 0)
        #expect(converted[topID]?.size == CGSize(width: 100, height: 80))
        #expect((converted[topID]?.minY ?? 0) > (converted[bottomID]?.minY ?? 0))
        // PaneGeometry semantiği: üst panel yukarıda
        #expect(PaneGeometry.neighbor(of: bottomID, direction: .up, frames: converted) == topID)
    }
}