package com.solevision.app.arfoot

import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

// TEMPORARY Phase-1b diagnostics — REMOVE ENTIRE FILE after the post-scan
// navigation root cause is confirmed and fixed (see
// PHASE_1B_ONDEVICE_DIAGNOSTICS_PROMPT.md Step 5).
//
// With adb unavailable on the test device, native-side events are invisible
// unless the app writes them down itself. This relay mirrors Kotlin events
// (activity lifecycle, AR session/view lifecycle, system-navigation
// observations) into the SAME nav_diag.log file the Dart DiagLogger writes,
// so lines from both sides interleave in wall-clock order.
//
// Reliability notes (post nav_diag (1).log analysis):
// - Writes are submitted synchronously per event to a serialized executor —
//   there is NO buffering, so a fast transition can never outrun a queued
//   write while the process lives. Only immediate process death can lose
//   already-submitted lines.
// - The stream is held OPEN persistently and each line is emitted as ONE
//   write() syscall on an O_APPEND descriptor. The earlier per-call
//   File.appendText() interleaved non-atomically with the Dart-side writer,
//   producing truncated/merged fragments in captured logs.
// - fd.sync() after each line makes it survive abrupt process death (the
//   crash signature this investigation chases).
// - Write failures are counted, not silently dropped: the running tally is
//   stamped into the next successful line so a capture can't silently lose
//   events without leaving a trace.
object DiagRelay {

    private const val TAG = "NavDiag"

    @Volatile private var filePath: String? = null
    @Volatile private var stream: FileOutputStream? = null

    // Written on the relay executor; read from any thread. Volatile is enough:
    // worst case a reader sees a slightly stale failure count.
    @Volatile private var failedWrites = 0

    // Single-thread executor: file IO off the main thread, writes serialized.
    private val executor = Executors.newSingleThreadExecutor()

    /** Called from Dart via the `setDiagLogFile` method channel. */
    fun setFile(path: String?) {
        filePath = path
        executor.execute {
            try {
                stream?.close()
            } catch (_: Exception) {}
            stream = null
            if (path == null) return@execute
            try {
                val file = File(path)
                if (!file.exists()) file.createNewFile()
                stream = FileOutputStream(file, true /* append */)
            } catch (e: Exception) {
                failedWrites++
                Log.e(TAG, "diag relay failed to open $path", e)
            }
        }
        log("native", "diag relay file set: $path")
    }

    fun log(source: String, message: String) {
        Log.i(TAG, "[$source] $message")
        if (filePath == null) return
        val stamped = "${timestamp()} [$source] $message"
        executor.execute {
            val out = stream ?: run { failedWrites++; return@execute }
            try {
                // Single write() of the whole line on an O_APPEND fd — atomic
                // vs the Dart-side writer, so no mid-line interleaving.
                out.write((stamped + "\n").toByteArray())
                out.fd.sync()
                if (failedWrites > 0) {
                    // Surface previously-swallowed failures inline so a
                    // captured log shows its own gaps.
                    out.write("... [relay] WARNING: $failedWrites earlier write(s) failed/dropped\n".toByteArray())
                    out.fd.sync()
                    failedWrites = 0
                }
            } catch (e: Exception) {
                failedWrites++
                Log.e(TAG, "diag write failed", e)
            }
        }
    }

    private fun timestamp(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date())
}
