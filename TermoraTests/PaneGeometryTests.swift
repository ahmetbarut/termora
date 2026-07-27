//
//  PaneGeometryTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@Suite("PaneGeometry")
struct PaneGeometryTests {

    // İki panel yan yana (AppKit: origin sol-alt).
    private struct SideBySide {
        let left = UUID()
        let right = UUID()
        var frames: [UUID: CGRect] {
            [left: CGRect(x: 0, y: 0, width: 100, height: 200),
             right: CGRect(x: 100, y: 0, width: 100, height: 200)]
        }
    }

    // Sol: tam boy. Sağ: alt (yüksek) ve üst (alçak) iki panel.
    private struct MixedLayout {
        let left = UUID()
        let rightBottom = UUID()
        let rightTop = UUID()
        var frames: [UUID: CGRect] {
            [left: CGRect(x: 0, y: 0, width: 100, height: 200),
             rightBottom: CGRect(x: 100, y: 0, width: 100, height: 120),
             rightTop: CGRect(x: 100, y: 120, width: 100, height: 80)]
        }
    }

    @Test("yan yana yerleşimde right ve left komşuları bulunur")
    func horizontalNeighbors() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .right, frames: layout.frames) == layout.right)
        #expect(PaneGeometry.neighbor(of: layout.right, direction: .left, frames: layout.frames) == layout.left)
    }

    @Test("yan yana yerleşimde dikey yönlerde komşu yoktur")
    func noVerticalNeighbors() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .up, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .down, frames: layout.frames) == nil)
    }

    @Test("kenardaki panelde yön dışına çıkınca nil döner")
    func edgeReturnsNil() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: layout.right, direction: .right, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .left, frames: layout.frames) == nil)
    }

    @Test("üç panelli yerleşimde en çok örtüşen aday seçilir")
    func picksLargestOverlap() {
        let layout = MixedLayout()
        // Sol panelin sağındaki iki aday: alt 120pt, üst 80pt örtüşür → alt kazanır.
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .right, frames: layout.frames) == layout.rightBottom)
        #expect(PaneGeometry.neighbor(of: layout.rightTop, direction: .left, frames: layout.frames) == layout.left)
        #expect(PaneGeometry.neighbor(of: layout.rightBottom, direction: .left, frames: layout.frames) == layout.left)
    }

    @Test("AppKit koordinatlarında up = daha büyük y")
    func appKitVerticalOrientation() {
        let layout = MixedLayout()
        #expect(PaneGeometry.neighbor(of: layout.rightBottom, direction: .up, frames: layout.frames) == layout.rightTop)
        #expect(PaneGeometry.neighbor(of: layout.rightTop, direction: .down, frames: layout.frames) == layout.rightBottom)
        #expect(PaneGeometry.neighbor(of: layout.rightTop, direction: .up, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.rightBottom, direction: .down, frames: layout.frames) == nil)
    }

    @Test("dik eksende örtüşmeyen aday komşu sayılmaz")
    func requiresPerpendicularOverlap() {
        let a = UUID(), b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0, width: 100, height: 100),
            b: CGRect(x: 100, y: 150, width: 100, height: 100)
        ]
        #expect(PaneGeometry.neighbor(of: a, direction: .right, frames: frames) == nil)
    }

    @Test("örtüşme eşitse en yakın aday seçilir")
    func tieBreaksOnDistance() {
        let current = UUID(), near = UUID(), far = UUID()
        let frames: [UUID: CGRect] = [
            current: CGRect(x: 0, y: 0, width: 100, height: 100),
            near: CGRect(x: 100, y: 0, width: 50, height: 100),
            far: CGRect(x: 150, y: 0, width: 50, height: 100)
        ]
        #expect(PaneGeometry.neighbor(of: current, direction: .right, frames: frames) == near)
    }

    @Test("bilinmeyen panel veya boş sözlük için nil döner")
    func unknownPaneReturnsNil() {
        let layout = SideBySide()
        #expect(PaneGeometry.neighbor(of: UUID(), direction: .right, frames: layout.frames) == nil)
        #expect(PaneGeometry.neighbor(of: layout.left, direction: .right, frames: [:]) == nil)
    }
}
