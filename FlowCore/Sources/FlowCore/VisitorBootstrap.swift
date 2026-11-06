// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client YouTube.visitorData and InnerTube.getSwJsData.
// Copyright (C) 2025-2026 A-EDev. Swift adaptation: 2026-11-06.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum VisitorBootstrap {
    public static func parse(_ data: Data) throws -> String {
        guard var body = String(data: data, encoding: .utf8) else { throw SearchError.invalidResponse }
        if body.hasPrefix(")]}'") {
            guard let newline = body.firstIndex(of: "\n") else { throw SearchError.invalidResponse }
            body = String(body[body.index(after: newline)...])
        }
        guard let json = body.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: json) as? [Any],
              let first = root.first as? [Any], first.count > 2,
              let values = first[2] as? [Any],
              let visitor = values.compactMap({ $0 as? String }).first(where: {
                  $0.hasPrefix("Cgt") || $0.hasPrefix("Cgs")
              }) else { throw SearchError.invalidResponse }
        return visitor
    }
}

actor VisitorSession {
    private let session: URLSession
    private var value: String?
    private var pending: Task<String?, Never>?
    private var lastAttempt: Date?
    init(session: URLSession) { self.session = session }

    func visitorData() async -> String? {
        if let value { return value }
        if let pending { return await pending.value }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return nil }
        lastAttempt = Date()
        let session = session
        let task = Task<String?, Never> {
            do {
                var request = URLRequest(url: URL(string: "https://music.youtube.com/sw.js_data")!)
                request.timeoutInterval = 10
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
                return try VisitorBootstrap.parse(data)
            } catch { return nil }
        }
        pending = task
        let result = await task.value
        value = result
        pending = nil
        return result
    }
}
