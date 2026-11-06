// SPDX-License-Identifier: GPL-3.0-only
// New main-frame confinement policy, 2026-11-06. Does not filter subframes/media resources.
import Foundation
public enum EmbeddedNavigationPolicy {
    public static func permitsMainFrame(_ url: URL?, video: VideoReference) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.port == nil,
              url.host?.lowercased() == video.embedURL.host, url.path == video.embedURL.path else { return false }
        return true
    }
}
