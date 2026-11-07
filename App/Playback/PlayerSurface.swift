// SPDX-License-Identifier: GPL-3.0-only
import AVKit
import SwiftUI

/// System player with PiP, AirPlay and native controls. Detaches from the player while
/// backgrounded so iOS keeps playing audio instead of pausing video.
struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.delegate = context.coordinator
        context.coordinator.attach(controller, player: player)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player, !context.coordinator.detached { controller.player = player }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private weak var controller: AVPlayerViewController?
        private weak var player: AVPlayer?
        private var pipActive = false
        private(set) var detached = false

        func attach(_ controller: AVPlayerViewController, player: AVPlayer) {
            self.controller = controller; self.player = player
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
            center.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }

        @objc private func background() {
            guard !pipActive else { return }
            detached = true
            controller?.player = nil
        }

        @objc private func foreground() {
            detached = false
            controller?.player = player
        }

        func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) { pipActive = true }
        func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) { pipActive = false }
    }
}

/// Bare video layer for the mini player.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private weak var player: AVPlayer?

        func configure(_ player: AVPlayer) {
            self.player = player
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        @objc private func background() { playerLayer.player = nil }
        @objc private func foreground() { playerLayer.player = player }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.configure(player)
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {}
}
