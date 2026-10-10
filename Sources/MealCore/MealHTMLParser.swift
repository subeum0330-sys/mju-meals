import Foundation

/// A deliberately narrow parser for the school's server-rendered five-column diet table.
/// Structural or date changes fail explicitly so another week's menu is never shown as current.
enum MealHTMLParser {
    private struct Cell {
        let html: String
        let header: Bool
        var text: String { plainText(html) }
    }

    private struct Span {
        let cell: Cell
        let remaining: Int
    }

    static func parse(_ html: String, cafeteria: Cafeteria, expectedMonday: Date,
                      fetchedAt: Date = Date()) throws -> MealWeek {
        guard let form = matches(#"<form\b([^>]*)>([\s\S]*?)</form\s*>"#, html)
            .first(where: { attributes($0[1])["id"] == "viewForm" }),
              attributes(form[1])["action"] == "/diet/mjukr/\(cafeteria.dietID)/view.do" else {
            throw MealServiceError.unexpectedPage
        }
        let inputs = matches(#"<input\b([^>]*)>"#, form[2]).map { attributes($0[1]) }
        guard let mondayText = inputs.first(where: { $0["name"] == "monday" })?["value"],
              let monday = SchoolCalendar.parseDate(mondayText) else {
            throw MealServiceError.unexpectedPage
        }
        guard monday == SchoolCalendar.startOfWeek(containing: expectedMonday) else {
            throw MealServiceError.mismatchedWeek
        }
        guard let table = matches(#"<table\b[^>]*>([\s\S]*?)</table\s*>"#, form[2]).first,
              let head = matches(#"<thead\b[^>]*>([\s\S]*?)</thead\s*>"#, table[1]).first,
              let body = matches(#"<tbody\b[^>]*>([\s\S]*?)</tbody\s*>"#, table[1]).first else {
            throw MealServiceError.unexpectedPage
        }
        let headers = matches(#"<th\b[^>]*>([\s\S]*?)</th\s*>"#, head[1]).map { plainText($0[1]) }
        guard headers == ["요일", "식단구분", "식단제목", "식단내용", "기타정보"] else {
            throw MealServiceError.unexpectedPage
        }
        let days = SchoolCalendar.weekDates(containing: monday)
        let rows = matches(#"<tr\b[^>]*>([\s\S]*?)</tr\s*>"#, body[1])
        guard !rows.isEmpty else { throw MealServiceError.malformedTable }
        var spans: [Int: Span] = [:]
        var entries: [MealEntry] = []
        for (rowIndex, row) in rows.enumerated() {
            var grid: [Int: Cell] = [:]
            var nextSpans: [Int: Span] = [:]
            for (column, span) in spans {
                grid[column] = span.cell
                if span.remaining > 1 {
                    nextSpans[column] = Span(cell: span.cell, remaining: span.remaining - 1)
                }
            }
            var column = 0
            for match in matches(#"<(th|td)\b([^>]*)>([\s\S]*?)</\1\s*>"#, row[1]) {
                while grid[column] != nil { column += 1 }
                let attrs = attributes(match[2])
                let rowSpan = Int(attrs["rowspan"] ?? "1") ?? 0
                let colSpan = Int(attrs["colspan"] ?? "1") ?? 0
                guard rowSpan > 0, rowSpan <= rows.count - rowIndex,
                      colSpan > 0, column + colSpan <= 5 else { throw MealServiceError.malformedTable }
                let cell = Cell(html: match[3], header: match[1].lowercased() == "th")
                for position in column..<(column + colSpan) {
                    guard grid[position] == nil else { throw MealServiceError.malformedTable }
                    grid[position] = cell
                    if rowSpan > 1 { nextSpans[position] = Span(cell: cell, remaining: rowSpan - 1) }
                }
                column += colSpan
            }
            spans = nextSpans
            guard grid.count == 5, let dateCell = grid[0], dateCell.header,
                  let dateParts = matches(#"^\s*(\d{1,2})\.(\d{1,2})(?:\s|$)"#, dateCell.text).first,
                  let month = Int(dateParts[1]), let day = Int(dateParts[2]),
                  let date = days.first(where: {
                      SchoolCalendar.calendar.component(.month, from: $0) == month &&
                      SchoolCalendar.calendar.component(.day, from: $0) == day
                  }), let categoryCell = grid[1], !categoryCell.text.isEmpty else {
                throw MealServiceError.malformedTable
            }
            let category: String
            switch categoryCell.text {
            case "점심": category = "중식"
            case "저녁": category = "석식"
            default: category = categoryCell.text
            }
            let missing = grid[3]!.text.contains("등록된 식단내용이(가) 없습니다")
            let title = missing ? nil : meaningful(grid[2]!.text)
            let items = missing ? [] : textLines(grid[3]!.html).compactMap(meaningful)
            let note = missing ? grid[3]!.text : meaningful(grid[4]!.text)
            entries.append(MealEntry(id: "\(cafeteria.id)-\(SchoolCalendar.dayKey(date))-\(category)-\(rowIndex)",
                                     date: date, category: category, title: title, items: items,
                                     note: note, isPublished: !missing && (title != nil || !items.isEmpty || note != nil)))
        }
        guard spans.isEmpty else { throw MealServiceError.malformedTable }
        let info = matches(#"<dl\b[^>]*>\s*<dt\b[^>]*>([\s\S]*?)</dt\s*>\s*<dd\b[^>]*>([\s\S]*?)</dd\s*>\s*</dl\s*>"#, html)
        let location = info.first(where: { plainText($0[1]) == "식당위치" }).flatMap { meaningful(plainText($0[2])) }
        let hours = info.first(where: { plainText($0[1]) == "운영시간" }).flatMap { meaningful(plainText($0[2])) }
        return MealWeek(cafeteria: cafeteria, monday: monday, entries: entries,
                        location: location, operatingHours: hours, fetchedAt: fetchedAt)
    }

    private static func meaningful(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "-" ? nil : value
    }

    private static func attributes(_ value: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in matches(#"([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, value) {
            result[match[1].lowercased()] = decodeEntities(match[2].isEmpty ? (match[3].isEmpty ? match[4] : match[3]) : match[2])
        }
        return result
    }

    private static func textLines(_ html: String) -> [String] {
        var value = replacing(#"<(script|style)\b[^>]*>[\s\S]*?</\1\s*>"#, in: html, with: "")
        value = replacing(#"<br\b[^>]*>|</(?:p|div|li)\s*>"#, in: value, with: "\n")
        value = replacing(#"<[^>]+>"#, in: value, with: "")
        value = decodeEntities(value)
        return value.components(separatedBy: .newlines).map {
            replacing(#"[\s\u00A0]+"#, in: $0, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private static func plainText(_ html: String) -> String { textLines(html).joined(separator: " ") }

    private static func decodeEntities(_ text: String) -> String {
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "middot": "·", "bull": "•", "ndash": "–", "mdash": "—", "hellip": "…",
            "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "hearts": "♥",
            "times": "×", "divide": "÷", "copy": "©", "reg": "®", "trade": "™"
        ]
        var output = text
        guard let regex = try? NSRegularExpression(pattern: #"&(#x[0-9A-Fa-f]+|#\d+|[A-Za-z]+);"#,
                                                    options: .caseInsensitive) else { return text }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let tokenRange = Range(match.range(at: 1), in: text), let fullRange = Range(match.range, in: output) else { continue }
            let token = String(text[tokenRange])
            let replacement: String?
            if token.lowercased().hasPrefix("#x") {
                replacement = UInt32(token.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map(String.init)
            } else if token.hasPrefix("#") {
                replacement = UInt32(token.dropFirst()).flatMap(UnicodeScalar.init).map(String.init)
            } else { replacement = named[token] }
            if let replacement { output.replaceSubrange(fullRange, with: replacement) }
        }
        return output
    }

    private static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}
