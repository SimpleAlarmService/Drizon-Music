#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Foundation

/// Flutter ⇄ Python bridge. Same channel name/methods the Android NewPipe
/// implementation uses, so Dart's MusicService works unchanged on both.
enum ExtractorChannel {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "music.extractor", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "search":
                send(["op": "search", "query": args["query"] ?? "", "limit": 20], result) { $0 }
            case "getStream":
                send(streamRequest(args), result) { ($0 as? [String: Any])?["url"] }
            case "getStreamInfo":
                send(streamRequest(args), result) { $0 }
            case "getVideoStreams":
                send(["op": "video",
                      "videoId": args["videoId"] ?? "",
                      "clientType": args["clientType"] ?? "ANDROID"], result) { $0 }
            case "muxVideo":
                guard let video = args["video"] as? String,
                      let audio = args["audio"] as? String,
                      let output = args["output"] as? String else {
                    return result(FlutterError(code: "ARGS", message: "video, audio and output paths required", details: nil))
                }
                VideoMuxer.mux(video: URL(fileURLWithPath: video),
                               audio: URL(fileURLWithPath: audio),
                               output: URL(fileURLWithPath: output)) { error in
                    DispatchQueue.main.async {
                        if let error {
                            result(FlutterError(code: "MUX", message: error.localizedDescription, details: nil))
                        } else {
                            result(output)
                        }
                    }
                }
            case "updateExtractor":
                send(["op": "update"], result) { $0 }
            case "checkExtractorUpdates":
                send(["op": "check"], result) { $0 }
            case "extractorVersion":
                send(["op": "version"], result) { $0 }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func streamRequest(_ args: [String: Any]) -> [String: Any] {
        ["op": "stream",
         "videoId": args["videoId"] ?? "",
         "clientType": args["clientType"] ?? "ANDROID",
         "quality": args["quality"] ?? "high"]
    }

    private static func send(_ payload: [String: Any],
                             _ result: @escaping FlutterResult,
                             transform: @escaping (Any) -> Any?) {
        PythonRuntime.shared.request(payload) { outcome in
            DispatchQueue.main.async {
                switch outcome {
                case .success(let data):
                    result(transform(data))
                case .failure(let error):
                    result(FlutterError(code: "EXTRACTOR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
}
