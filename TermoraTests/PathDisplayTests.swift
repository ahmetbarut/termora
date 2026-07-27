import Testing
@testable import Termora

@Suite("PathDisplay")
@MainActor
struct PathDisplayTests {

    @Test func replacesHomePrefixWithTilde() {
        #expect(PathDisplay.abbreviate("/Users/ahmet/Apps/Termora", home: "/Users/ahmet") == "~/Apps/Termora")
    }

    @Test func homeItselfBecomesTilde() {
        #expect(PathDisplay.abbreviate("/Users/ahmet", home: "/Users/ahmet") == "~")
        #expect(PathDisplay.abbreviate("/Users/ahmet", home: "/Users/ahmet/") == "~")
    }

    @Test func doesNotMatchPartialDirectoryName() {
        #expect(PathDisplay.abbreviate("/Users/ahmetbarut/Apps", home: "/Users/ahmet") == "/Users/ahmetbarut/Apps")
    }

    @Test func leavesUnrelatedPathsUntouched() {
        #expect(PathDisplay.abbreviate("/tmp/build", home: "/Users/ahmet") == "/tmp/build")
        #expect(PathDisplay.abbreviate("/tmp/build", home: "") == "/tmp/build")
    }
}
