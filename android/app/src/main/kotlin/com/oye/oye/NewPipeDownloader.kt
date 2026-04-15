package com.oye.oye

import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * HTTP downloader implementation required by NewPipe Extractor.
 * Uses plain HttpURLConnection — no external dependencies.
 */
class NewPipeDownloader private constructor() : Downloader() {

    companion object {
        val instance: NewPipeDownloader by lazy { NewPipeDownloader() }
        private const val TIMEOUT_MS = 30_000
        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/130.0.6723.103 Mobile Safari/537.36"
    }

    @Throws(IOException::class)
    override fun execute(request: Request): Response {
        val conn = URL(request.url()).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout    = TIMEOUT_MS
            conn.requestMethod  = request.httpMethod()

            // Set default headers
            conn.setRequestProperty("User-Agent", USER_AGENT)

            // Set caller-provided headers
            for ((key, values) in request.headers()) {
                for (value in values) {
                    conn.setRequestProperty(key, value)
                }
            }

            // Write request body if present
            val body = request.dataToSend()
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body) }
            }

            conn.connect()

            val responseCode = conn.responseCode
            val responseBody = try {
                (if (responseCode < 400) conn.inputStream else conn.errorStream)
                    ?.bufferedReader()
                    ?.readText()
                    ?: ""
            } catch (_: Exception) { "" }

            val responseHeaders = mutableMapOf<String, List<String>>()
            for ((key, values) in conn.headerFields) {
                if (key != null) responseHeaders[key] = values
            }

            return Response(responseCode, conn.responseMessage, responseHeaders, responseBody, request.url())
        } finally {
            conn.disconnect()
        }
    }
}
