package com.oye.oye

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.schabi.newpipe.extractor.NewPipe

class MainActivity : AudioServiceActivity() {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val CHANNEL = "music.extractor"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialise NewPipe Extractor with our HTTP downloader
        try {
            NewPipe.init(NewPipeDownloader.instance)
        } catch (e: Exception) {
            // Already initialised — safe to ignore
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "search"    -> handleSearch(call.argument("query") ?: "", result)
                    "getStream" -> handleGetStream(call.argument("videoId") ?: "", result)
                    else        -> result.notImplemented()
                }
            }
    }

    // ── Search ─────────────────────────────────────────────────────────────────

    private fun handleSearch(query: String, result: MethodChannel.Result) {
        if (query.isBlank()) {
            result.error("INVALID_QUERY", "Query must not be empty", null)
            return
        }

        scope.launch {
            try {
                val tracks = MusicRepository.searchTracks(query)

                val trackMaps = tracks.map { t ->
                    mapOf(
                        "videoId"     to t.videoId,
                        "title"       to t.title,
                        "artist"      to t.artist,
                        "thumbnail"   to t.thumbnail,
                        "duration"    to t.duration,
                        "durationSec" to t.durationSec,
                    )
                }

                withContext(Dispatchers.Main) {
                    result.success(trackMaps)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("SEARCH_ERROR", e.message ?: "Search failed", null)
                }
            }
        }
    }

    // ── Stream extraction ──────────────────────────────────────────────────────

    private fun handleGetStream(videoId: String, result: MethodChannel.Result) {
        if (videoId.isBlank()) {
            result.error("INVALID_VIDEO_ID", "videoId must not be empty", null)
            return
        }

        scope.launch {
            try {
                val url = MusicRepository.getAudioStreamUrl(videoId)
                withContext(Dispatchers.Main) {
                    result.success(url)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("STREAM_ERROR", e.message ?: "Stream extraction failed", null)
                }
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
