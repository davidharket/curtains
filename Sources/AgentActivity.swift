import Darwin
import Foundation
import SQLite3

struct WorkingAgent: Equatable {
    enum Kind { case claude, codex }
    let id: String
    let kind: Kind
    let note: String
}

struct AgentActivity: Equatable {
    var agents: [WorkingAgent] = []

    static func current() -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        let claudeHome = environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        return Self(agents: (claudeAgents(in: claudeHome) + codexAgents(in: codexHome)).sorted { $0.id < $1.id })
    }

    private struct ClaudeSession: Decodable {
        let pid: Int32
        let status: String
        let name: String?
        let startedAt: Double
    }

    static func claudeAgents(in home: URL) -> [WorkingAgent] {
        let directory = home.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json",
                  let pid = Int32(file.deletingPathExtension().lastPathComponent), pid > 0,
                  let data = try? Data(contentsOf: file),
                  let session = try? JSONDecoder().decode(ClaudeSession.self, from: data),
                  session.pid == pid, session.status == "busy" else { return nil }
            // A stale session file can outlive its process, and macOS can reuse the PID.
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  Double(info.pbi_start_tvsec) <= session.startedAt / 1000 + 1 else { return nil }
            let topic = (session.name ?? "").lowercased()
            let summaries = [
                (["video", "render"], "Video work"),
                (["test", "testing"], "Testing"),
                (["bug", "feil", "debug"], "Debugging"),
                (["design", "layout"], "Design work"),
                (["research", "analyse"], "Analysis")
            ]
            let note = summaries.first { words, _ in words.contains(where: topic.contains) }?.1 ?? "Working…"
            return WorkingAgent(id: "claude-\(pid)-\(session.startedAt)", kind: .claude, note: note)
        }
    }

    static func codexAgents(in home: URL) -> [WorkingAgent] {
        let directory = home.appendingPathComponent("thread-writer-locks")
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        var db: OpaquePointer?
        let path = home.appendingPathComponent("thread_history_1.sqlite").path
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(db, 150)
        var query: OpaquePointer?
        defer { sqlite3_finalize(query) }
        let sql = "SELECT status, turn_id FROM thread_turns WHERE thread_id = ? ORDER BY rollout_ordinal DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK else { return [] }

        // Optional status detail. Older schemas can still report a busy turn.
        var latest: OpaquePointer?
        defer { sqlite3_finalize(latest) }
        let detail = "SELECT item_type FROM thread_items WHERE thread_id=? AND turn_id=? ORDER BY rollout_ordinal DESC LIMIT 1"
        sqlite3_prepare_v2(db, detail, -1, &latest, nil)
        return files.compactMap { file in
            let thread = file.deletingPathExtension().lastPathComponent
            guard file.pathExtension == "lock", UUID(uuidString: thread) != nil,
                  writerIsLive(file) else { return nil }
            return thread.withCString { id in
                sqlite3_bind_text(query, 1, id, -1, nil)
                defer { sqlite3_reset(query); sqlite3_clear_bindings(query) }
                guard sqlite3_step(query) == SQLITE_ROW, let status = sqlite3_column_text(query, 0)
                else { return nil }
                guard String(cString: status) == "inProgress" else { return nil }
                var note = "Working…"
                if let latest, let turn = sqlite3_column_text(query, 1) {
                    sqlite3_bind_text(latest, 1, id, -1, nil)
                    sqlite3_bind_text(latest, 2, turn, -1, nil)
                    defer { sqlite3_reset(latest); sqlite3_clear_bindings(latest) }
                    if sqlite3_step(latest) == SQLITE_ROW, let type = sqlite3_column_text(latest, 0) {
                        switch String(cString: type) {
                        case "commandExecution": note = "Using terminal"
                        case "fileChange": note = "Editing files"
                        case "reasoning": note = "Thinking…"
                        case "webSearch": note = "Searching the web"
                        case "imageView": note = "Checking an image"
                        case "mcpToolCall": note = "Using a tool"
                        case "agentMessage": note = "Writing…"
                        default: break
                        }
                    }
                }
                return WorkingAgent(id: thread, kind: .codex, note: note)
            }
        }
    }

    private static func writerIsLive(_ file: URL) -> Bool {
        let fd = open(file.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // F_GETLK only inspects the writer's lock. It never acquires a competing lock.
        var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_RDLCK), l_whence: Int16(SEEK_SET))
        return fcntl(fd, F_GETLK, &lock) == 0 && lock.l_type == F_WRLCK
    }
}
