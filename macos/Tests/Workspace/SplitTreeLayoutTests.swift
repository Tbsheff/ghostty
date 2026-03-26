import Foundation
import Testing
@testable import Ghostty

/// Tests for SplitTreeLayout serialization round-trips.
///
/// Since inflate() requires a live ghostty_app_t, these tests focus on:
/// - Constructing SplitTreeLayout values directly
/// - Encoding/decoding via Codable (JSON round-trip)
/// - Verifying structure is preserved
struct SplitTreeLayoutTests {

    // MARK: - Helpers

    private func makeSingleLeaf(uuid: String = UUID().uuidString, pwd: String? = "/tmp") -> SplitTreeLayout {
        SplitTreeLayout(
            root: .leaf(SurfaceLayout(uuid: uuid, pwd: pwd, title: "Terminal", isUserSetTitle: false)),
            zoomedPath: nil
        )
    }

    private func makeHorizontalSplit() -> SplitTreeLayout {
        SplitTreeLayout(
            root: .split(SplitLayout(
                direction: .horizontal,
                ratio: 0.5,
                left: .leaf(SurfaceLayout(uuid: "left-uuid", pwd: "/tmp/left", title: "Left", isUserSetTitle: false)),
                right: .leaf(SurfaceLayout(uuid: "right-uuid", pwd: "/tmp/right", title: "Right", isUserSetTitle: false))
            )),
            zoomedPath: nil
        )
    }

    private func makeVerticalSplit() -> SplitTreeLayout {
        SplitTreeLayout(
            root: .split(SplitLayout(
                direction: .vertical,
                ratio: 0.6,
                left: .leaf(SurfaceLayout(uuid: "top-uuid", pwd: "/tmp/top", title: "Top", isUserSetTitle: false)),
                right: .leaf(SurfaceLayout(uuid: "bottom-uuid", pwd: "/tmp/bottom", title: "Bottom", isUserSetTitle: false))
            )),
            zoomedPath: nil
        )
    }

    private func makeNestedSplit() -> SplitTreeLayout {
        SplitTreeLayout(
            root: .split(SplitLayout(
                direction: .horizontal,
                ratio: 0.5,
                left: .leaf(SurfaceLayout(uuid: "a", pwd: "/a", title: "A", isUserSetTitle: false)),
                right: .split(SplitLayout(
                    direction: .vertical,
                    ratio: 0.3,
                    left: .leaf(SurfaceLayout(uuid: "b", pwd: "/b", title: "B", isUserSetTitle: false)),
                    right: .leaf(SurfaceLayout(uuid: "c", pwd: "/c", title: "C", isUserSetTitle: false))
                ))
            )),
            zoomedPath: nil
        )
    }

    // MARK: - Capture Tests (structural construction)

    @Test func capture_singleLeaf_capturesCorrectly() {
        let layout = makeSingleLeaf(uuid: "test-uuid", pwd: "/home/user")

        guard case .leaf(let surface) = layout.root else {
            Issue.record("expected leaf node")
            return
        }
        #expect(surface.uuid == "test-uuid")
        #expect(surface.pwd == "/home/user")
    }

    @Test func capture_horizontalSplit_capturesDirectionAndRatio() {
        let layout = makeHorizontalSplit()

        guard case .split(let split) = layout.root else {
            Issue.record("expected split node")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(abs(split.ratio - 0.5) < 0.001)
    }

    @Test func capture_verticalSplit_capturesDirectionAndRatio() {
        let layout = makeVerticalSplit()

        guard case .split(let split) = layout.root else {
            Issue.record("expected split node")
            return
        }
        #expect(split.direction == .vertical)
        #expect(abs(split.ratio - 0.6) < 0.001)
    }

    @Test func capture_nestedSplits_capturesFullTree() {
        let layout = makeNestedSplit()

        guard case .split(let outer) = layout.root else {
            Issue.record("expected outer split")
            return
        }
        #expect(outer.direction == .horizontal)

        // Left should be a leaf
        guard case .leaf(let leftLeaf) = outer.left else {
            Issue.record("expected left leaf")
            return
        }
        #expect(leftLeaf.uuid == "a")

        // Right should be another split
        guard case .split(let inner) = outer.right else {
            Issue.record("expected inner split")
            return
        }
        #expect(inner.direction == .vertical)
        #expect(abs(inner.ratio - 0.3) < 0.001)
    }

    // MARK: - Codable Round-Trip

    @Test func codable_roundTrip_preservesStructure() throws {
        let original = makeNestedSplit()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitTreeLayout.self, from: data)

        guard case .split(let outer) = decoded.root else {
            Issue.record("expected split after decode")
            return
        }
        #expect(outer.direction == .horizontal)

        guard case .split(let inner) = outer.right else {
            Issue.record("expected inner split after decode")
            return
        }
        #expect(inner.direction == .vertical)
        #expect(abs(inner.ratio - 0.3) < 0.001)

        guard case .leaf(let leaf) = inner.right else {
            Issue.record("expected leaf after decode")
            return
        }
        #expect(leaf.uuid == "c")
        #expect(leaf.pwd == "/c")
    }

    @Test func codable_singleLeaf_roundTrips() throws {
        let original = makeSingleLeaf(uuid: "solo", pwd: "/solo")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SplitTreeLayout.self, from: data)

        guard case .leaf(let surface) = decoded.root else {
            Issue.record("expected leaf after decode")
            return
        }
        #expect(surface.uuid == "solo")
        #expect(surface.pwd == "/solo")
        #expect(surface.title == "Terminal")
    }

    @Test func codable_complexTree_roundTrips() throws {
        let original = makeNestedSplit()

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Double round-trip to ensure stability
        let data1 = try encoder.encode(original)
        let decoded1 = try decoder.decode(SplitTreeLayout.self, from: data1)
        let data2 = try encoder.encode(decoded1)
        let decoded2 = try decoder.decode(SplitTreeLayout.self, from: data2)

        // Verify the second decode still has the full structure
        guard case .split(let outer) = decoded2.root else {
            Issue.record("expected split on double round-trip")
            return
        }
        guard case .leaf(let a) = outer.left else {
            Issue.record("expected leaf a")
            return
        }
        #expect(a.uuid == "a")
    }

    // MARK: - SurfaceLayout Fields

    @Test func surfaceLayout_capturesPwd() {
        let surface = SurfaceLayout(uuid: "id", pwd: "/home/test", title: nil, isUserSetTitle: false)
        #expect(surface.pwd == "/home/test")
    }

    @Test func surfaceLayout_capturesTitle() {
        let surface = SurfaceLayout(uuid: "id", pwd: nil, title: "My Terminal", isUserSetTitle: false)
        #expect(surface.title == "My Terminal")
    }

    @Test func surfaceLayout_capturesUUID() {
        let surface = SurfaceLayout(uuid: "specific-uuid", pwd: nil, title: nil, isUserSetTitle: false)
        #expect(surface.uuid == "specific-uuid")
    }

    // MARK: - Zoomed Path

    @Test func zoomedPath_noZoom_isNil() {
        let layout = makeSingleLeaf()
        #expect(layout.zoomedPath == nil)
    }

    @Test func zoomedPath_roundTrips() throws {
        let layout = SplitTreeLayout(
            root: .split(SplitLayout(
                direction: .horizontal,
                ratio: 0.5,
                left: .leaf(SurfaceLayout(uuid: "l", pwd: nil, title: nil, isUserSetTitle: false)),
                right: .leaf(SurfaceLayout(uuid: "r", pwd: nil, title: nil, isUserSetTitle: false))
            )),
            zoomedPath: [.right]
        )

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(SplitTreeLayout.self, from: data)
        #expect(decoded.zoomedPath == [.right])
    }

    // MARK: - JSON Compactness

    @Test func json_isCompact() throws {
        let layout = makeSingleLeaf(uuid: "x", pwd: "/x")
        let encoder = JSONEncoder()
        // Don't use prettyPrinted — default is compact
        let data = try encoder.encode(layout)
        let json = String(data: data, encoding: .utf8)!
        // Compact JSON should not have leading whitespace or newlines
        #expect(!json.contains("\n"))
        // Should contain the essential keys
        #expect(json.contains("\"uuid\""))
        #expect(json.contains("\"type\""))
    }
}
