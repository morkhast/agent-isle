import XCTest
@testable import AgentIsle

/// Local: pollers refresh every session on each scan; the list must stay ordered by each
/// session's own last activity, not by which one the scan happened to refresh last.
@MainActor
final class SessionOrderTests: XCTestCase {
    func testPollerRefreshKeepsLastActivityOrder() {
        let store = SessionStore()
        let now = Date()
        let recent = UUID(), stale = UUID()
        store.upsert(AgentSession(id: recent, agent: .claude, title: "recent", terminal: "T",
                                  lastMessage: "", status: .idle,
                                  updatedAt: now.addingTimeInterval(-60)))
        store.upsert(AgentSession(id: stale, agent: .claude, title: "stale", terminal: "T",
                                  lastMessage: "", status: .idle,
                                  updatedAt: now.addingTimeInterval(-86_400)))
        // A scan refreshes newest first, so the stale one is touched last.
        store.update(id: recent, touch: false) { $0.updatedAt = now.addingTimeInterval(-60) }
        store.update(id: stale, touch: false) { $0.updatedAt = now.addingTimeInterval(-86_400) }
        XCTAssertEqual(store.orderedSessions.map(\.title), ["recent", "stale"])
    }

    func testEventUpdateStillCountsAsActivity() {
        let store = SessionStore()
        let a = UUID(), b = UUID()
        store.upsert(AgentSession(id: a, agent: .claude, title: "a", terminal: "T",
                                  lastMessage: "", status: .idle, updatedAt: Date().addingTimeInterval(-60)))
        store.upsert(AgentSession(id: b, agent: .claude, title: "b", terminal: "T",
                                  lastMessage: "", status: .idle, updatedAt: Date().addingTimeInterval(-30)))
        store.update(id: a) { $0.lastMessage = "hook event" }
        XCTAssertEqual(store.orderedSessions.first?.title, "a")
    }
}

/// Local: the row's time label is time since last activity, not session age.
final class ElapsedTextTests: XCTestCase {
    func testLabelCountsFromLastActivity() {
        let now = Date()
        let s = AgentSession(agent: .claude, title: "t", terminal: "T", lastMessage: "",
                             status: .idle, startedAt: now.addingTimeInterval(-35 * 3600),
                             updatedAt: now.addingTimeInterval(-5 * 60))
        XCTAssertEqual(s.elapsedText, "5m")
    }
}
