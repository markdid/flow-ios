// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift subset of YouTubeTakeoutCsvParser.kt, modified 2026-11-06.
import Foundation

public enum TakeoutPreview: Sendable {
    case subscriptions([LocalSubscription], skipped: Int)
    case playlist([VideoReference], skipped: Int)
}
public enum TakeoutError: LocalizedError {
    case limit, malformed, unsupported
    public var errorDescription: String? {
        switch self {
        case .limit: return "This import exceeds 10 MB, 10,000 data rows, 32 columns or the 16,000-character field limit. Nothing was imported."
        case .malformed: return "The file is not valid UTF-8 CSV. Malformed quoting rejects the whole file; nothing was imported."
        case .unsupported: return "This is not a supported Takeout subscriptions or playlist-video CSV. A header and a valid first data row are required. ZIP, history, playlist metadata and music-library files are not supported."
        }
    }
}
public enum TakeoutCSV {
    public static let maximumBytes = 10_000_000
    public static let maximumRows = 10_000
    public static func preview(_ data: Data, importedAt: Date = Date()) throws -> TakeoutPreview {
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw TakeoutError.limit }
        guard var text = String(data: data, encoding: .utf8) else { throw TakeoutError.malformed }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = try records(text)
        guard rows.count >= 2 else { throw TakeoutError.unsupported }
        let header = rows[0], first = rows[1]
        if header.count >= 3, subscription(header, date: importedAt) == nil, subscription(first, date: importedAt) != nil {
            var seen = Set<String>(); var result: [LocalSubscription] = []; var skipped = 0
            for row in rows.dropFirst() {
                try Task.checkCancellation()
                if let value = subscription(row, date: importedAt), seen.insert(value.id).inserted { result.append(value) }
                else { skipped += 1 }
            }
            return .subscriptions(result, skipped: skipped)
        }
        if header.count == 2, videoID(header) == nil, videoID(first) != nil {
            var seen = Set<String>(); var result: [VideoReference] = []; var skipped = 0
            for row in rows.dropFirst() {
                try Task.checkCancellation()
                if let id = videoID(row), seen.insert(id).inserted {
                    result.append(try VideoReference(url: URL(string: "https://www.youtube.com/watch?v=\(id)")!, title: id, addedAt: importedAt))
                } else { skipped += 1 }
            }
            return .playlist(result, skipped: skipped)
        }
        throw TakeoutError.unsupported
    }
    private static func subscription(_ row: [String], date: Date) -> LocalSubscription? {
        guard row.count >= 3 else { return nil }
        let id = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let name = row[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard ChannelBrowseClient.validChannelID(id), !name.isEmpty, name.utf16.count <= 1000,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 }),
              let url = URLComponents(string: row[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), ["youtube.com", "www.youtube.com"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              ["/channel/" + id, "/channel/" + id + "/"].contains(url.path) else { return nil }
        return LocalSubscription(id: id, name: name, subscribedAt: date)
    }
    private static func videoID(_ row: [String]) -> String? {
        guard row.count == 2 else { return nil }
        let id = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.utf8.count == 11, id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let timestamp = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if !timestamp.isEmpty {
            let pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,9})?(?:Z|[+-](?:0[0-9]|1[0-7]):[0-5][0-9]|[+-]18:00)$"#
            guard timestamp.range(of: pattern, options: .regularExpression) != nil else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if formatter.date(from: timestamp) == nil {
                formatter.formatOptions = [.withInternetDateTime]
                guard formatter.date(from: timestamp) != nil else { return nil }
            }
            // Reject normalized invalid calendar dates (e.g. February 31), not just syntax.
            guard timestamp.count >= 20 else { return nil }
            let prefix = String(timestamp.prefix(10)).split(separator: "-")
            guard prefix.count == 3, let year = Int(prefix[0]), let month = Int(prefix[1]), let day = Int(prefix[2]), (1...9999).contains(year) else { return nil }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components), calendar.component(.year, from: date) == year, calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else { return nil }
        }
        return id
    }
    /// Strict CSV grammar. Whole-file limits are checked before any library mutation.
    private static func records(_ text: String) throws -> [[String]] {
        let chars = Array(text.unicodeScalars)
        var rows: [[String]] = []; var row: [String] = []; var field = String.UnicodeScalarView()
        var quoted = false; var closed = false; var index = 0; var fieldCount = 0
        func appendField() throws {
            row.append(String(field)); field = String.UnicodeScalarView(); fieldCount = 0; closed = false
            guard row.count <= 32 else { throw TakeoutError.limit }
        }
        func appendRow() throws {
            try appendField()
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
            row = []
            guard rows.count <= maximumRows + 1 else { throw TakeoutError.limit }
        }
        while index < chars.count {
            if index % 1024 == 0 { try Task.checkCancellation() }
            let char = chars[index]
            guard char.value != 0 else { throw TakeoutError.malformed }
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append(char); fieldCount += 1; index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(char); fieldCount += 1 }
            } else if char == "," { try appendField() }
            else if char == "\r" || char == "\n" {
                try appendRow()
                if char == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
            } else if char == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard char != "\"", !closed, char.value != 0 else { throw TakeoutError.malformed }
                field.append(char); fieldCount += 1
            }
            guard fieldCount <= 16_000 else { throw TakeoutError.limit }
            index += 1
        }
        guard !quoted else { throw TakeoutError.malformed }
        if !field.isEmpty || !row.isEmpty || closed { try appendRow() }
        return rows
    }
}
