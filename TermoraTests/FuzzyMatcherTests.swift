import Foundation
import Testing
@testable import Termora

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    // MARK: - Eşleşme / eşleşmeme

    @Test func emptyQueryMatchesEverythingWithNeutralScore() throws {
        let match = try #require(FuzzyMatcher.match("", in: "New Tab"))
        #expect(match.score == 0)
        #expect(match.matchedIndices.isEmpty)
    }

    @Test func returnsNilWhenCharactersAreMissing() {
        #expect(FuzzyMatcher.match("xyz", in: "New Tab") == nil)
        // Doğru harfler, YANLIŞ sıra: alt dizi eşleşmesi olmadığı için sonuç yok.
        #expect(FuzzyMatcher.match("bat", in: "New Tab") == nil)
        #expect(FuzzyMatcher.match("newtabs", in: "New Tab") == nil)
    }

    @Test func matchesIgnoringCase() throws {
        let lower = try #require(FuzzyMatcher.match("nt", in: "New Tab"))
        let upper = try #require(FuzzyMatcher.match("NT", in: "New Tab"))
        #expect(lower == upper)
    }

    // MARK: - Vurgulama için indeksler

    @Test func reportsMatchedCharacterIndices() throws {
        let match = try #require(FuzzyMatcher.match("nt", in: "New Tab"))
        #expect(match.matchedIndices == [0, 4])
    }

    @Test func indicesAreOffsetsIntoTheOriginalCandidate() throws {
        let match = try #require(FuzzyMatcher.match("split", in: "Split Vertically"))
        #expect(match.matchedIndices == [0, 1, 2, 3, 4])
    }

    // MARK: - Puanlama kuralları

    @Test func wordStartMatchesOutrankMidWordMatches() throws {
        let wordStarts = try #require(FuzzyMatcher.match("nt", in: "New Tab"))
        let midWord = try #require(FuzzyMatcher.match("nt", in: "Increment"))
        #expect(wordStarts.score > midWord.score)
    }

    @Test func firstCharacterMatchOutranksLaterWordStart() throws {
        let atStart = try #require(FuzzyMatcher.match("t", in: "Tab"))
        let laterWord = try #require(FuzzyMatcher.match("t", in: "New Tab"))
        #expect(atStart.score > laterWord.score)
    }

    @Test func consecutiveRunOutranksScatteredMatch() throws {
        let consecutive = try #require(FuzzyMatcher.match("clo", in: "Close Pane"))
        let scattered = try #require(FuzzyMatcher.match("clo", in: "Cancel Log Output"))
        #expect(consecutive.score > scattered.score)
    }

    @Test func camelCaseBoundaryCountsAsWordStart() throws {
        let camel = try #require(FuzzyMatcher.match("nt", in: "newTab"))
        let plain = try #require(FuzzyMatcher.match("nt", in: "newtab"))
        #expect(camel.score > plain.score)
    }

    @Test func picksTheBestPathInsteadOfTheLeftmostOne() throws {
        // Soldan açgözlü tarama [1, 3] verirdi; en iyi yol bitişik "ab" çiftidir.
        let match = try #require(FuzzyMatcher.match("ab", in: "xa b ab"))
        #expect(match.matchedIndices == [5, 6])
    }

    @Test func scoringIsDeterministic() throws {
        let first = try #require(FuzzyMatcher.match("fp", in: "Focus Pane Left"))
        let second = try #require(FuzzyMatcher.match("fp", in: "Focus Pane Left"))
        #expect(first == second)
    }

    @Test func trimsSurroundingWhitespaceInTheQuery() throws {
        let padded = try #require(FuzzyMatcher.match("  nt  ", in: "New Tab"))
        let plain = try #require(FuzzyMatcher.match("nt", in: "New Tab"))
        #expect(padded == plain)
    }

    @Test func handlesQueriesLongerThanTheCandidate() {
        #expect(FuzzyMatcher.match("new tab please", in: "New Tab") == nil)
    }
}
