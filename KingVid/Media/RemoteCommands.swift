import Foundation
import MediaPlayer
import AVFoundation

enum RemoteAction {
    case play, pause, toggle, next, previous
    case skip(Double)
    case seek(Double)
}

/// Registers Lock Screen / Control Center / headphone commands.
///
/// Deliberately NOT main-actor isolated: MediaPlayer invokes these handlers on a background
/// queue, and closures created inside a main-actor type would inherit that isolation and trap.
final class RemoteCommands {
    private let handler: @Sendable (RemoteAction) -> Void

    init(handler: @escaping @Sendable (RemoteAction) -> Void) {
        self.handler = handler
        let center = MPRemoteCommandCenter.shared()
        let handler = self.handler

        center.playCommand.addTarget { _ in handler(.play); return .success }
        center.pauseCommand.addTarget { _ in handler(.pause); return .success }
        center.togglePlayPauseCommand.addTarget { _ in handler(.toggle); return .success }
        center.nextTrackCommand.addTarget { _ in handler(.next); return .success }
        center.previousTrackCommand.addTarget { _ in handler(.previous); return .success }
        center.skipForwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            handler(.skip(interval))
            return .success
        }
        center.skipBackwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            handler(.skip(-interval))
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            handler(.seek(e.positionTime))
            return .success
        }
    }

    /// Enables/disables the commands to match the current media.
    func configure(enabled: Bool, hasNext: Bool, hasPrevious: Bool, live: Bool, skipInterval: Double) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.nextTrackCommand.isEnabled = enabled && hasNext
        center.previousTrackCommand.isEnabled = enabled && hasPrevious
        center.skipForwardCommand.isEnabled = enabled && !live
        center.skipBackwardCommand.isEnabled = enabled && !live
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.changePlaybackPositionCommand.isEnabled = enabled && !live
    }

    /// Builds artwork outside any actor so MediaPlayer can call the request handler from any queue.
    static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

/// Plays a silent, looping buffer so iOS keeps the app process alive while web media is
/// briefly stalled or paused in the background. Optional (Settings > Background Playback).
final class SilentKeepAlive {
    private var player: AVAudioPlayer?

    func start() {
        if player == nil {
            player = try? AVAudioPlayer(data: Self.silentWAV(seconds: 1))
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.prepareToPlay()
        }
        if player?.isPlaying == false { player?.play() }
    }

    func stop() {
        player?.stop()
    }

    private static func silentWAV(seconds: Int) -> Data {
        let sampleRate = 8000
        let dataSize = sampleRate * seconds * 2
        var data = Data()
        func append32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)                       // PCM
        append16(1)                       // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))  // byte rate
        append16(2)                       // block align
        append16(16)                      // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
