//
//  SplitLayoutMathTests.swift
//  TermoraTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Termora

@Suite("SplitLayoutMath")
struct SplitLayoutMathTests {

    @Test("ayraç kalınlığı 6pt ve iki panel + ayraç toplam uzunluğu doldurur")
    func lengthsFillTotal() {
        #expect(SplitLayoutMath.dividerThickness == 6)

        let total: CGFloat = 200
        let first = SplitLayoutMath.firstLength(totalLength: total, ratio: 0.5)
        let second = SplitLayoutMath.secondLength(totalLength: total, ratio: 0.5)
        #expect(first == 97)
        #expect(second == 97)
        #expect(first + second + SplitLayoutMath.dividerThickness == total)
    }

    @Test("oran uzunluklara doğrusal yansır")
    func lengthsFollowRatio() {
        let total: CGFloat = 406            // usable = 400
        #expect(SplitLayoutMath.usableLength(totalLength: total) == 400)
        #expect(SplitLayoutMath.firstLength(totalLength: total, ratio: 0.25) == 100)
        #expect(SplitLayoutMath.secondLength(totalLength: total, ratio: 0.25) == 300)
    }

    @Test("çok küçük veya sıfır alanda uzunluklar negatife düşmez")
    func degenerateSizes() {
        #expect(SplitLayoutMath.usableLength(totalLength: 0) == 0)
        #expect(SplitLayoutMath.usableLength(totalLength: 4) == 0)
        #expect(SplitLayoutMath.firstLength(totalLength: 0, ratio: 0.5) == 0)
        #expect(SplitLayoutMath.secondLength(totalLength: 0, ratio: 0.5) == 0)
    }

    @Test("sürükleme konumu orana çevrilir ve 0.15...0.85 aralığına kırpılır")
    func ratioFromPosition() {
        #expect(SplitLayoutMath.ratio(atPosition: 50, totalLength: 100) == 0.5)
        #expect(SplitLayoutMath.ratio(atPosition: 20, totalLength: 100) == 0.2)
        #expect(SplitLayoutMath.ratio(atPosition: 0, totalLength: 100) == 0.15)
        #expect(SplitLayoutMath.ratio(atPosition: -40, totalLength: 100) == 0.15)
        #expect(SplitLayoutMath.ratio(atPosition: 100, totalLength: 100) == 0.85)
        #expect(SplitLayoutMath.ratio(atPosition: 400, totalLength: 100) == 0.85)
    }

    @Test("sıfır uzunlukta oran 0.5'e düşer")
    func ratioWithZeroLength() {
        #expect(SplitLayoutMath.ratio(atPosition: 10, totalLength: 0) == 0.5)
    }
}