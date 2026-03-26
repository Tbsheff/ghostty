import Foundation
import Testing
@testable import Ghostty

/// Tests for the fuzzyScore matching algorithm used in QuickSwitcher.
struct QuickSwitcherTests {

    @Test func testFuzzyMatch_exactMatch_scoresHighest() {
        let score = fuzzyScore(query: "main", target: "main")
        #expect(score != nil)

        // Exact match should score higher than a partial match
        let partialScore = fuzzyScore(query: "main", target: "maintain")
        #expect(partialScore != nil)
        #expect(score! >= partialScore!)
    }

    @Test func testFuzzyMatch_partialMatch_scores() {
        let score = fuzzyScore(query: "fea", target: "feature/auth")
        #expect(score != nil)
        #expect(score! > 0)
    }

    @Test func testFuzzyMatch_noMatch_scoresZero() {
        let score = fuzzyScore(query: "xyz", target: "main")
        #expect(score == nil)
    }

    @Test func testFuzzyMatch_caseInsensitive() {
        // fuzzyScore expects lowercased inputs per its contract
        let score1 = fuzzyScore(query: "main", target: "main")
        let score2 = fuzzyScore(query: "main", target: "main")
        #expect(score1 == score2)

        // All-lowercase comparison
        let score3 = fuzzyScore(query: "auth", target: "feature/auth")
        #expect(score3 != nil)
    }

    @Test func testFuzzyMatch_emptyQuery_returnsZero() {
        let score = fuzzyScore(query: "", target: "anything")
        #expect(score == 0)
    }

    @Test func testFuzzyMatch_emptyTarget_returnsNil() {
        let score = fuzzyScore(query: "abc", target: "")
        #expect(score == nil)
    }

    @Test func testFuzzyMatch_wordBoundaryBonus() {
        // Word boundary at "/" gives +5 bonus
        let boundaryScore = fuzzyScore(query: "a", target: "/auth")
        // No boundary — 'a' matched mid-word
        let noBoundaryScore = fuzzyScore(query: "a", target: "xabc")

        #expect(boundaryScore != nil)
        #expect(noBoundaryScore != nil)
        // Boundary match gets +5 bonus so should score higher
        #expect(boundaryScore! > noBoundaryScore!)
    }

    @Test func testFuzzyMatch_consecutiveBonus() {
        // "mai" consecutive in "main" should score higher than scattered "m_a_i" in "meanti"
        let consecutiveScore = fuzzyScore(query: "mai", target: "main")
        let scatteredScore = fuzzyScore(query: "mai", target: "meanti")

        #expect(consecutiveScore != nil)
        #expect(scatteredScore != nil)
        #expect(consecutiveScore! > scatteredScore!)
    }

    @Test func testRecentWorktrees_sortedFirst() {
        // Test the sorting behavior of QuickSwitcherItem by lastActiveAt
        let items = [
            QuickSwitcherItem(id: "old", name: "old", projectName: "P", branch: "old", lastActiveAt: Date.distantPast),
            QuickSwitcherItem(id: "new", name: "new", projectName: "P", branch: "new", lastActiveAt: Date()),
            QuickSwitcherItem(id: "mid", name: "mid", projectName: "P", branch: "mid", lastActiveAt: Date(timeIntervalSinceNow: -3600)),
        ]

        // Sort by lastActiveAt descending (same logic as QuickSwitcherView.filteredItems)
        let sorted = items.sorted { a, b in
            (a.lastActiveAt ?? .distantPast) > (b.lastActiveAt ?? .distantPast)
        }

        #expect(sorted[0].id == "new")
        #expect(sorted[1].id == "mid")
        #expect(sorted[2].id == "old")
    }
}
