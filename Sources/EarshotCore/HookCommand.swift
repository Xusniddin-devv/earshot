import Foundation

/// The body of `earshot hook`: turn Claude Code's hook stdin into one event-log line.
/// Never throws and never prints, so Claude Code is never affected.
public func runHook(stdin: Data, env: [String: String], ppid: Int32, tree: ProcessTree,
                    log: EventLog, now: Date) {
    if env["EARSHOT_INTERNAL"] == "1" { return }
    guard let obj = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any],
          let name = obj["hook_event_name"] as? String,
          let kind = EventKind(rawValue: name),
          let sessionId = obj["session_id"] as? String
    else { return }
    // Subagents report through the parent session; ignore their events.
    if obj["agent_id"] != nil { return }
    var message = obj["last_assistant_message"] as? String
    // StopFailure: last_assistant_message is the rendered API error; fall back to the raw fields.
    if kind == .stopFailure, message == nil {
        message = obj["error_details"] as? String ?? obj["error"] as? String
    }

    let e = HookEvent(kind: kind,
                      sessionId: sessionId,
                      cwd: obj["cwd"] as? String ?? "",
                      tty: resolveTTY(start: ppid, tree: tree),
                      time: now,
                      lastMessage: message,
                      notificationType: obj["notification_type"] as? String,
                      source: obj["source"] as? String)
    try? log.append(e)
}
