// SPDX-License-Identifier: GPL-3.0-only
// New portable playback-intent policy, 2026-11-06.
import Foundation

public enum PlaybackStartPolicy {
    /// An initial source resolves asynchronously: it must honor a Pause received while waiting.
    /// Source replacement preserves actual playback/waiting state or an explicit pending Play.
    public static func shouldStart(firstSource: Bool, requested: Bool, pendingPlay: Bool, actualRate: Double, waiting: Bool) -> Bool {
        if firstSource { return requested }
        return pendingPlay || (actualRate.isFinite && actualRate != 0) || waiting
    }
    /// Source restoration never guesses whether an AVKit pause was intentional.
    public static func shouldStartAfterSeek(sourceRestoration: Bool, explicitReplay: Bool, pendingPlay: Bool, requested: Bool) -> Bool {
        !sourceRestoration && requested && (explicitReplay || pendingPlay)
    }
    public static func shouldRestart(ended: Bool, position: Double, duration: Double) -> Bool {
        ended || (position.isFinite && duration.isFinite && duration > 0 && position >= duration)
    }
}
