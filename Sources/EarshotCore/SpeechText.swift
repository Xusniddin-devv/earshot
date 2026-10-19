import Foundation

/// Turns a Claude reply (markdown) into short chunks that sound right when spoken.
public enum SpeechText {
    public static func chunks(from markdown: String, maxChars: Int = 280) -> [String] {
        var lines: [String] = []
        var codeLines: Int?
        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let n = codeLines {
                    lines.append(codeMarker(n))
                    codeLines = nil
                } else {
                    codeLines = 0
                }
                continue
            }
            if let n = codeLines {
                codeLines = n + 1
                continue
            }
            if let line = speakable(trimmed), !line.isEmpty { lines.append(line) }
        }
        if let n = codeLines { lines.append(codeMarker(n)) }

        return lines.flatMap(sentences).flatMap { split($0, maxChars: maxChars) }
    }

    static func codeMarker(_ n: Int) -> String {
        "Code block, \(n) \(n == 1 ? "line" : "lines")."
    }

    /// One markdown line → plain text, or nil for lines that should not be read.
    static func speakable(_ line: String) -> String? {
        var s = line
        // Table separator rows like |---|:--:|
        if s.hasPrefix("|"), s.allSatisfy({ "|-: ".contains($0) }) { return nil }
        if s.hasPrefix("|") {
            let cells = s.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            s = cells.joined(separator: ", ")
        }
        s = replace(s, #"^#{1,6}\s+"#, "")
        s = replace(s, #"^>\s?"#, "")
        s = replace(s, #"^([-*+]|\d+[.)])\s+"#, "")
        s = replace(s, #"\[([^\]]+)\]\([^)]*\)"#, "$1")
        s = replace(s, #"https?://\S+?(?=[.,;:!?)]?(\s|$))"#, "link")
        s = s.replacingOccurrences(of: "`", with: "")
        s = replace(s, #"(?:~|\.{1,2})?/?(?:[\w@.-]+/)+([\w@-][\w@.-]*)"#, "$1")
        s = replace(s, #"\*\*(.+?)\*\*"#, "$1")
        s = replace(s, #"__(.+?)__"#, "$1")
        s = replace(s, #"(?<![\w*])\*(\S(?:.*?\S)?)\*(?![\w*])"#, "$1")
        s = replace(s, #"(?<!\w)_(\S(?:.*?\S)?)_(?!\w)"#, "$1")
        s = replace(s, #"\s+"#, " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func sentences(_ line: String) -> [String] {
        let marked = replace(line, #"([.!?])\s+"#, "$1\u{0}")
        return marked.split(separator: "\u{0}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Splits text longer than `maxChars` at the last ", " or space before the limit.
    static func split(_ text: String, maxChars: Int) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while rest.count > maxChars {
            let window = rest.prefix(maxChars + 1)
            var cut = window.endIndex
            var resume = window.endIndex
            if let comma = window.range(of: ", ", options: .backwards), comma.lowerBound > rest.startIndex {
                cut = rest.index(after: comma.lowerBound)
                resume = comma.upperBound
            } else if let space = window.lastIndex(of: " "), space > rest.startIndex {
                cut = space
                resume = rest.index(after: space)
            } else {
                cut = rest.index(rest.startIndex, offsetBy: maxChars)
                resume = cut
            }
            out.append(String(rest[..<cut]).trimmingCharacters(in: .whitespaces))
            rest = rest[resume...]
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
