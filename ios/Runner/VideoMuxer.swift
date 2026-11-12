import AVFoundation
import Foundation

/// Joins a video-only MP4 (H.264) and an audio-only M4A (AAC) into one MP4.
/// YouTube serves 720p and above as separate video and audio streams. AVFoundation
/// can copy both tracks into one file without re-encoding (passthrough), so no
/// ffmpeg is needed.
enum VideoMuxer {
    struct MuxError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func mux(video: URL, audio: URL, output: URL, completion: @escaping (Error?) -> Void) {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
            return completion(MuxError(message: "No video track in \(video.lastPathComponent)"))
        }
        guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first else {
            return completion(MuxError(message: "No audio track in \(audio.lastPathComponent)"))
        }

        let composition = AVMutableComposition()
        let duration = CMTimeMinimum(videoAsset.duration, audioAsset.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        do {
            guard
                let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                return completion(MuxError(message: "Could not create composition tracks"))
            }
            try v.insertTimeRange(range, of: videoTrack, at: .zero)
            try a.insertTimeRange(range, of: audioTrack, at: .zero)
            v.preferredTransform = videoTrack.preferredTransform
        } catch {
            return completion(error)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            return completion(MuxError(message: "Passthrough export is not available"))
        }
        try? FileManager.default.removeItem(at: output)
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
            completion(export.status == .completed
                ? nil
                : (export.error ?? MuxError(message: "Export ended with status \(export.status.rawValue)")))
        }
    }
}
