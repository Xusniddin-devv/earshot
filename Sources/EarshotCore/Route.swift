public enum RouteDecision: Equatable, Sendable {
    case type(tty: String)
    case refuse(reason: String)
}

/// Where spoken text goes. Uses the tab focused when the key was *released*, and never guesses.
public func route(focusedTTYAtRelease focused: String?, ownTTY: String?, knownTTYs: Set<String>,
                  transcript: String) -> RouteDecision {
    if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .refuse(reason: "heard nothing") }
    guard let focused else { return .refuse(reason: "Terminal is not in front") }
    if focused == ownTTY { return .refuse(reason: "dashboard tab is focused") }
    guard knownTTYs.contains(focused) else { return .refuse(reason: "focused tab is not a Claude session") }
    return .type(tty: focused)
}
