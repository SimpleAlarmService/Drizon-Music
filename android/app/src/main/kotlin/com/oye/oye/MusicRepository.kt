package com.oye.oye

import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfoItem

/**
 * YouTube Music search + stream extraction via NewPipe Extractor.
 * Uses StreamInfo.getInfo() for reliable stream extraction.
 */
object MusicRepository {

    data class TrackInfo(
        val videoId: String,
        val title: String,
        val artist: String,
        val thumbnail: String,
        val duration: String,
        val durationSec: Int,
    )

    // ── Search ─────────────────────────────────────────────────────────────────

    fun searchTracks(query: String): List<TrackInfo> {
        val extractor = ServiceList.YouTube.getSearchExtractor(query)
        extractor.fetchPage()

        val results = mutableListOf<TrackInfo>()
        val seenIds = mutableSetOf<String>()

        for (infoItem in extractor.initialPage.items) {
            if (infoItem !is StreamInfoItem) continue
            try {
                val videoId = extractVideoId(infoItem.url ?: continue) ?: continue
                if (!seenIds.add(videoId)) continue

                // Best thumbnail: use highest resolution available
                val thumb = infoItem.thumbnails
                    .maxByOrNull { (it.width ?: 0) * (it.height ?: 0) }
                    ?.url ?: ""

                val durSec = maxOf(infoItem.duration, 0L)

                results.add(
                    TrackInfo(
                        videoId     = videoId,
                        title       = infoItem.name ?: "Unknown",
                        artist      = infoItem.uploaderName ?: "",
                        thumbnail   = thumb,
                        duration    = formatDuration(durSec),
                        durationSec = durSec.toInt(),
                    )
                )
                if (results.size >= 20) break
            } catch (_: Exception) { /* skip malformed items */ }
        }
        return results
    }

    // ── Stream extraction ──────────────────────────────────────────────────────
    // Uses StreamInfo.getInfo() which is the recommended way — it handles
    // all stream types, signature decryption, and manifest resolution.

    fun getAudioStreamUrl(videoId: String): String {
        val watchUrl = "https://www.youtube.com/watch?v=$videoId"

        // StreamInfo.getInfo() does full extraction including sig deciphering
        val info = StreamInfo.getInfo(ServiceList.YouTube, watchUrl)

        val streams: List<AudioStream> = info.audioStreams
        if (streams.isEmpty()) throw Exception("No audio streams for $videoId")

        // Prefer PROGRESSIVE_HTTP (direct URLs, no manifest needed)
        val progressive = streams.filter { s ->
            s.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP &&
            !s.content.isNullOrEmpty()
        }

        val best: AudioStream = if (progressive.isNotEmpty()) {
            // Among progressive streams, pick highest bitrate
            progressive.maxByOrNull { it.averageBitrate }!!
        } else {
            // Fall back to any stream with content (HLS/DASH — just_audio handles these)
            streams.filter { !it.content.isNullOrEmpty() }
                .maxByOrNull { it.averageBitrate }
                ?: throw Exception("No playable audio stream for $videoId")
        }

        return best.content ?: throw Exception("Stream content is null for $videoId")
    }

    // ── Video streams ──────────────────────────────────────────────────────────
    // Same shape the iOS (yt-dlp) side returns, so Dart picks formats once:
    // {headers, hls, formats: [{url, kind, ext, height, bitrate, vcodec, acodec}]}

    fun getVideoStreams(videoId: String): Map<String, Any?> {
        val info = StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/watch?v=$videoId")
        val formats = mutableListOf<Map<String, Any?>>()

        fun add(url: String?, kind: String, ext: String?, height: Int, bitrate: Int,
                vcodec: String?, acodec: String?) {
            if (url.isNullOrEmpty()) return
            formats.add(mapOf(
                "url" to url, "kind" to kind, "ext" to (ext ?: ""), "height" to height,
                "bitrate" to bitrate, "vcodec" to (vcodec ?: ""), "acodec" to (acodec ?: ""),
            ))
        }

        for (s in info.videoStreams) {          // video + audio in one file
            if (s.deliveryMethod != DeliveryMethod.PROGRESSIVE_HTTP) continue
            add(s.content, "muxed", s.format?.suffix, s.height, s.bitrate, s.codec, "mp4a")
        }
        for (s in info.videoOnlyStreams) {
            if (s.deliveryMethod != DeliveryMethod.PROGRESSIVE_HTTP) continue
            add(s.content, "video", s.format?.suffix, s.height, s.bitrate, s.codec, null)
        }
        for (s in info.audioStreams) {
            if (s.deliveryMethod != DeliveryMethod.PROGRESSIVE_HTTP) continue
            add(s.content, "audio", s.format?.suffix, 0, s.averageBitrate * 1000, null, s.codec)
        }

        return mapOf(
            "headers" to emptyMap<String, String>(),
            "hls" to info.hlsUrl?.ifEmpty { null },
            "formats" to formats,
            "title" to info.name,
            "durationSec" to info.duration.toInt(),
        )
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun extractVideoId(url: String): String? {
        val idx = url.indexOf("v=")
        if (idx < 0) return null
        return url.substring(idx + 2)
            .substringBefore("&")
            .substringBefore("?")
            .trim()
            .ifEmpty { null }
    }

    private fun formatDuration(seconds: Long): String {
        val m = seconds / 60
        val s = seconds % 60
        return "$m:${s.toString().padStart(2, '0')}"
    }
}
