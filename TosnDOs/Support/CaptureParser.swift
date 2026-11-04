import Foundation
import CoreGraphics

/// One OCR line plus its box. Bottom-left origin because that is what Vision
/// returns, and the position is what ties "明天 3 点" to the right line.
struct RecognizedLine: Equatable {
    var text: String
    var minX: CGFloat
    var maxX: CGFloat
    var midY: CGFloat
    var height: CGFloat
}

/// A task pulled out of a screenshot, before the user confirms it.
struct CapturedTask: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var dueDate: Date?
    var hasTime: Bool
    var place: String?
    var sourceLine: String

    var isEmptyTitle: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Turns raw OCR lines into candidate tasks. Deliberately conservative: a false
/// positive costs the user a tap in the confirm sheet, a false negative costs
/// them the whole point of the feature. Nothing here talks to the network.
enum CaptureParser {

    /// Lines already on the same row (a title on the left, a time on the right)
    /// get glued together before anything is parsed.
    static func rows(from lines: [RecognizedLine]) -> [String] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.midY > $1.midY }

        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if var last = rows.last,
               let reference = last.first,
               abs(reference.midY - line.midY) < max(reference.height, line.height) * 0.6 {
                last.append(line)
                rows[rows.count - 1] = last
            } else {
                rows.append([line])
            }
        }

        return rows.map { row in
            row.sorted { $0.minX < $1.minX }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }
    }

    static func parse(
        lines: [RecognizedLine],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [CapturedTask] {
        var seen = Set<String>()
        var result: [CapturedTask] = []

        // A "地点：" line is a modifier: merge it into the row above.
        var merged: [String] = []
        for row in rows(from: lines) {
            if isModifier(row), !merged.isEmpty {
                merged[merged.count - 1] += " " + row
            } else {
                merged.append(row)
            }
        }

        for row in merged {
            guard isCandidate(row) else { continue }

            var working = stripMarkers(row)
            var place: String?
            if let found = extractPlace(from: working) {
                place = found.value
                working.removeSubrange(found.range)
            }
            let withoutPlace = working

            // NaturalDateParser both extracts the date and hands back the
            // leftover words, which is exactly the title we want.
            let parsed = NaturalDateParser.parse(withoutPlace, now: now, calendar: calendar)
            let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty, title.count <= 200 else { continue }

            let key = title.lowercased() + "|" + (parsed.dueDate.map { String(Int($0.timeIntervalSince1970 / 86_400)) } ?? "-")
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            result.append(
                CapturedTask(
                    title: title,
                    dueDate: parsed.dueDate,
                    hasTime: parsed.hasTime,
                    place: place,
                    sourceLine: row
                )
            )

            if result.count >= 30 { break }
        }

        return result
    }

    // MARK: - Candidate detection

    private static let markers = ["☐", "□", "○", "◯", "•", "-", "·", "✓", "✔", "[ ]", "[x]", "*"]

    private static func isCandidate(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return false }

        if markers.contains(where: { trimmed.hasPrefix($0) }) { return true }
        if trimmed.range(of: #"^\d{1,2}[.、)]"#, options: .regularExpression) != nil { return true }
        if trimmed.contains("待办") || trimmed.lowercased().contains("todo") { return true }

        // Short, comma-free lines only.
        guard trimmed.count <= 40, !trimmed.contains("，"), !trimmed.contains(",") else { return false }
        if dateDetector.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }

        return false
    }

    private static let modifierPrefixes = ["地点：", "地点:", "地址：", "地址:", "位置：", "位置:", "时间：", "时间:"]

    private static func isModifier(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        if modifierPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }
        // A row holding nothing but a time is also a modifier.
        let ns = trimmed as NSString
        if let match = dateDetector.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length)) {
            return match.range.length >= trimmed.count - 1
        }
        return false
    }

    private static func stripMarkers(_ row: String) -> String {
        var text = row.trimmingCharacters(in: .whitespaces)
        for marker in markers where text.hasPrefix(marker) {
            text.removeFirst(marker.count)
            text = text.trimmingCharacters(in: .whitespaces)
            break
        }
        if let range = text.range(of: #"^\d{1,2}[.、)]\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Place

    private static let placePrefixes = ["地点：", "地点:", "地址：", "地址:", "位置：", "位置:"]

    struct PlaceMatch {
        var value: String
        var range: Range<String.Index>
    }

    static func extractPlace(from text: String) -> PlaceMatch? {
        for prefix in placePrefixes {
            guard let prefixRange = text.range(of: prefix) else { continue }
            let tail = text[prefixRange.upperBound...]
            let cut = tail.firstIndex { "，,。;；|｜".contains($0) } ?? tail.endIndex
            let value = String(tail[..<cut]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            return PlaceMatch(value: value, range: prefixRange.lowerBound..<cut)
        }

        if let match = text.range(of: #"@\s*[^\s，,。]{2,}"#, options: .regularExpression) {
            let value = String(text[match])
                .replacingOccurrences(of: "@", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return PlaceMatch(value: value, range: match) }
        }

        let ns = text as NSString
        if let found = addressDetector.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
           found.range.length > 0,
           let range = Range(found.range, in: text) {
            return PlaceMatch(value: ns.substring(with: found.range), range: range)
        }

        if let match = text.range(of: #"(在|于)\s*[^\s，,。]{2,}(店|楼|室|号|路|街|中心|广场|大厦)"#, options: .regularExpression) {
            let value = String(text[match])
                .replacingOccurrences(of: "在", with: "")
                .replacingOccurrences(of: "于", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return PlaceMatch(value: value, range: match) }
        }

        return nil
    }

    private static let dateDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let addressDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
}
