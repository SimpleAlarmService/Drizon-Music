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
