package com.oye.oye

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Joins a video-only MP4 (H.264) and an audio-only M4A (AAC) into one MP4 by
 * copying samples (no re-encoding). YouTube serves 720p+ as separate streams.
 */
object VideoMuxer {

    fun mux(videoPath: String, audioPath: String, outputPath: String) {
        File(outputPath).delete()
        val video = MediaExtractor().apply { setDataSource(videoPath) }
        val audio = MediaExtractor().apply { setDataSource(audioPath) }
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            val vIn = selectTrack(video, "video/")
            val aIn = selectTrack(audio, "audio/")
            val vOut = muxer.addTrack(video.getTrackFormat(vIn))
            val aOut = muxer.addTrack(audio.getTrackFormat(aIn))
            muxer.start()
            copy(video, muxer, vOut)
            copy(audio, muxer, aOut)
            muxer.stop()
        } finally {
            muxer.release()
            video.release()
            audio.release()
        }
    }

    private fun selectTrack(extractor: MediaExtractor, mimePrefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(android.media.MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(mimePrefix)) {
                extractor.selectTrack(i)
                return i
            }
        }
        throw IllegalArgumentException("No $mimePrefix track found")
    }

    private fun copy(extractor: MediaExtractor, muxer: MediaMuxer, track: Int) {
        val buffer = ByteBuffer.allocate(4 * 1024 * 1024)
        val info = MediaCodec.BufferInfo()
        while (true) {
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) break
            info.offset = 0
            info.size = size
            info.presentationTimeUs = extractor.sampleTime
            info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
            muxer.writeSampleData(track, buffer, info)
            extractor.advance()
        }
    }
}
