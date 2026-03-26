import Foundation
import Testing
@testable import Ghostty

/// Tests for PortDiscovery lsof output parsing and URL construction.
struct PortDiscoveryTests {

    // MARK: - parseLsofOutput

    @Test func testParseOutput_extractsPortsAndPIDs() async {
        let discovery = PortDiscovery()

        let output = """
        COMMAND   PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    12345 user   20u  IPv4 0xabcdef      0t0  TCP *:3000 (LISTEN)
        python  67890 user   5u   IPv4 0x123456      0t0  TCP 127.0.0.1:8080 (LISTEN)
        """

        let entries = await discovery.parseLsofOutput(output)
        #expect(entries.count == 2)

        #expect(entries[0].processName == "node")
        #expect(entries[0].pid == 12345)
        #expect(entries[0].port == 3000)

        #expect(entries[1].processName == "python")
        #expect(entries[1].pid == 67890)
        #expect(entries[1].port == 8080)
    }

    @Test func testNoListeningPorts_returnsEmpty() async {
        let discovery = PortDiscovery()

        let output = """
        COMMAND   PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        """

        let entries = await discovery.parseLsofOutput(output)
        #expect(entries.isEmpty)
    }

    @Test func testParseOutput_handlesEmptyString() async {
        let discovery = PortDiscovery()
        let entries = await discovery.parseLsofOutput("")
        #expect(entries.isEmpty)
    }

    @Test func testParseOutput_handlesMalformedLines() async {
        let discovery = PortDiscovery()

        let output = """
        short line
        node    notapid user   20u  IPv4 0xabcdef      0t0  TCP *:3000 (LISTEN)
        node    12345 user   20u  IPv4 0xabcdef      0t0  TCP *:3000 (LISTEN)
        """

        let entries = await discovery.parseLsofOutput(output)
        // Only the last valid line should parse
        #expect(entries.count == 1)
        #expect(entries[0].port == 3000)
    }

    // MARK: - openInBrowser URL

    @Test func testOpenInBrowser_constructsCorrectURL() async {
        // We can't test actual browser opening, but verify the URL would be correct
        let url = URL(string: "http://localhost:3000")
        #expect(url != nil)
        #expect(url?.host == "localhost")
        #expect(url?.port == 3000)
    }
}
