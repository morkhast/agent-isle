import AppKit

/// Local: bridge to the Herdr terminal multiplexer. CLI sessions here run in Herdr panes
/// (TERM_PROGRAM=herdr), so the hook can't name a host app to jump to. Herdr itself knows
/// which pane runs which Claude session (`herdr agent list` → agent_session.value), so we
/// ask it: to focus the exact pane on jump, and to tell a live waiting session from a
/// closed one when pruning.
enum Herdr {
    private static let binary: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in ["\(home)/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }()

    private static let lock = NSLock()
    private static var cached: (at: Date, panes: [String: String]?, focused: String?)?
    private static var cachedHost: (at: Date, bundleID: String?)?

    /// Claude session id (lowercased) → Herdr pane id for every agent Herdr tracks.
    /// Nil when Herdr isn't installed or its server isn't reachable.
    static func panesBySession(maxAge: TimeInterval = 0) -> [String: String]? {
        snapshot(maxAge: maxAge).panes
    }

    /// Claude session id (lowercased) of the pane focused in Herdr, if it runs an agent.
    static func focusedSession(maxAge: TimeInterval = 0) -> String? {
        snapshot(maxAge: maxAge).focused
    }

    /// Bundle id of the terminal app hosting the Herdr client (cached for a minute).
    static func hostBundleID() -> String? {
        lock.lock()
        let hit = cachedHost
        lock.unlock()
        if let hit, Date().timeIntervalSince(hit.at) < 60 { return hit.bundleID }
        let id = hostApp()?.bundleIdentifier
        lock.lock()
        cachedHost = (Date(), id)
        lock.unlock()
        return id
    }

    private static func snapshot(maxAge: TimeInterval) -> (panes: [String: String]?, focused: String?) {
        if maxAge > 0 {
            lock.lock()
            let hit = cached
            lock.unlock()
            if let hit, Date().timeIntervalSince(hit.at) < maxAge { return (hit.panes, hit.focused) }
        }
        let fresh = fetchPanes()
        lock.lock()
        cached = (Date(), fresh?.panes, fresh?.focused)
        lock.unlock()
        return (fresh?.panes, fresh?.focused)
    }

    /// Focus the pane running `sessionID` and bring the terminal hosting Herdr to the front.
    /// Returns false when Herdr doesn't know this session, so the caller falls back.
    static func focus(sessionID: String) -> Bool {
        guard let pane = panesBySession()?[sessionID.lowercased()],
              run(["agent", "focus", pane]) != nil else { return false }
        if let app = hostApp(), let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        return true
    }

    /// Submit `text` to the agent in `pane` (Herdr pastes it and presses Enter) — no focus
    /// change, no keystroke synthesis. Blocking: call off the main thread.
    static func prompt(pane: String, text: String) -> Bool {
        run(["agent", "prompt", pane, text]) != nil
    }

    private static func fetchPanes() -> (panes: [String: String], focused: String?)? {
        guard let data = run(["agent", "list"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let agents = result["agents"] as? [[String: Any]] else { return nil }
        var map: [String: String] = [:]
        var focused: String?
        for agent in agents {
            guard let pane = agent["pane_id"] as? String,
                  let session = agent["agent_session"] as? [String: Any],
                  let id = session["value"] as? String else { continue }
            map[id.lowercased()] = pane
            if agent["focused"] as? Bool == true { focused = id.lowercased() }
        }
        return (map, focused)
    }

    /// The GUI app the Herdr client runs in: find the client process (`herdr` with no
    /// subcommand) and walk up its parents to the first regular app.
    private static func hostApp() -> NSRunningApplication? {
        guard let data = run(["-axo", "pid=,ppid=,args="], executable: "/bin/ps"),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var parent: [Int32: Int32] = [:]
        var clients: [Int32] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            parent[pid] = ppid
            if parts.count == 3 {
                let args = parts[2].trimmingCharacters(in: .whitespaces)
                if args == "herdr" || args.hasSuffix("/herdr") { clients.append(pid) }
            }
        }
        for client in clients {
            var pid = client
            for _ in 0..<16 {
                guard let next = parent[pid], next > 1 else { break }
                pid = next
                if let app = NSRunningApplication(processIdentifier: pid),
                   app.activationPolicy == .regular {
                    return app
                }
            }
        }
        return nil
    }

    private static func run(_ args: [String], executable: String? = nil) -> Data? {
        guard let path = executable ?? binary else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return proc.terminationStatus == 0 ? data : nil
    }
}
