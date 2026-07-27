import AppKit
import Testing
@testable import Termora

@MainActor
@Suite struct NSColorHexTests {
    @Test func parsesSixDigitHexWithHash() throws {
        let color = try #require(NSColor(hexString: "#FF8000"))
        let rgb = try #require(color.usingColorSpace(.sRGB))
        #expect(abs(rgb.redComponent - 1.0) < 0.001)
        #expect(abs(rgb.greenComponent - 128.0 / 255.0) < 0.001)
        #expect(abs(rgb.blueComponent - 0.0) < 0.001)
        #expect(abs(rgb.alphaComponent - 1.0) < 0.001)
    }

    @Test func parsesLowercaseWithoutHash() throws {
        let color = try #require(NSColor(hexString: "1a2b3c"))
        let rgb = try #require(color.usingColorSpace(.sRGB))
        #expect(abs(rgb.redComponent - CGFloat(0x1A) / 255.0) < 0.001)
        #expect(abs(rgb.greenComponent - CGFloat(0x2B) / 255.0) < 0.001)
        #expect(abs(rgb.blueComponent - CGFloat(0x3C) / 255.0) < 0.001)
    }

    @Test func parsesEightDigitHexWithAlpha() throws {
        let color = try #require(NSColor(hexString: "#FF800080"))
        let rgb = try #require(color.usingColorSpace(.sRGB))
        #expect(abs(rgb.redComponent - 1.0) < 0.001)
        #expect(abs(rgb.alphaComponent - 128.0 / 255.0) < 0.001)
    }

    @Test(arguments: ["", "#", "#FFF", "12345", "#GGGGGG", "not-a-color", "#FFFFFFF"])
    func invalidStringsReturnNil(input: String) {
        #expect(NSColor(hexString: input) == nil)
    }
}
