package com.solevision.app.footdetector

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.max

/** Method channel — the Dart twin is `kOnnxFootDetectorChannel` in `onnx_foot_detector.dart`. */
const val ONNX_FOOT_DETECTOR_CHANNEL = "com.solevision/onnx_foot_detector"

/**
 * Android-only custom foot detector (YOLO11n-pose → ONNX).
 *
 * Loads the bundled `assets/models/foot-v1.onnx` (via flutter_assets) into
 * ONNX Runtime and runs one NV21 frame per call. Preprocessing and decode
 * mirror `customer-portal/src/lib/footTracker.worker.js` exactly (cover
 * letterbox on #808080, /255 CHW float32, output [1,11,N] as
 * cx,cy,w,h,boxConf,heelX,heelY,heelC,toeX,toeY,toeC, thresholds 0.35/0.3,
 * NMS IoU 0.45, top-2) so the two apps can never disagree about a frame.
 *
 * iOS has no twin: [OnnxFootDetector] never calls this channel off Android
 * and every controller falls back to ML Kit segmentation there.
 */
class OnnxFootDetectorPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Guarded by `lock`.
    private val lock = Any()
    private var env: ai.onnxruntime.OrtEnvironment? = null
    private var session: ai.onnxruntime.OrtSession? = null
    private var loadError: String? = null
    // V4.9 device fix: `detectFoot` spawns one thread per call and two Dart
    // loops can call at once — but OrtSession.run is not safe for concurrent
    // use, and the P30 Pro died with a SIGSEGV null-deref inside
    // libonnxruntime on exactly that overlap (tombstones 11:40/11:43). An
    // overlapped call is answered `busy` and dropped: the detectors already
    // treat a dropped frame as a missed sample, never an error.
    private val inFlight = java.util.concurrent.atomic.AtomicBoolean(false)

    fun registerWith(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ONNX_FOOT_DETECTOR_CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
        synchronized(lock) {
            try { session?.close() } catch (_: Exception) {}
            try { env?.close() } catch (_: Exception) {}
            session = null
            env = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detectFoot" -> {
                val data = call.argument<ByteArray>("nv21")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val rotation = call.argument<Int>("rotationDegrees") ?: 0
                if (data == null || width <= 0 || height <= 0) {
                    result.error("bad-args", "nv21/width/height required", null)
                    return
                }
                if (!inFlight.compareAndSet(false, true)) {
                    result.error("busy", "inference already running", null)
                    return
                }
                // Inference blocks ~50-150 ms: never on the platform thread.
                Thread {
                    try {
                        val out = runInference(data, width, height, rotation)
                        mainHandler.post { result.success(out) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("inference-failed", e.message, null) }
                    } finally {
                        inFlight.set(false)
                    }
                }.start()
            }
            "close" -> {
                synchronized(lock) {
                    try { session?.close() } catch (_: Exception) {}
                    try { env?.close() } catch (_: Exception) {}
                    session = null
                    env = null
                    loadError = null
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureSessionLocked(): ai.onnxruntime.OrtSession {
        session?.let { return it }
        loadError?.let { throw IllegalStateException(it) }
        try {
            val e = ai.onnxruntime.OrtEnvironment.getEnvironment()
            env = e
            val modelFile = cachedModelFile()
            val opts = ai.onnxruntime.OrtSession.SessionOptions()
            session = e.createSession(modelFile.absolutePath, opts)
            return session!!
        } catch (t: Throwable) {
            loadError = t.message ?: "ort-load-failed"
            throw IllegalStateException(loadError, t)
        }
    }

    /** Copy-once the flutter_asset into getFilesDir so ORT gets a file path. */
    private fun cachedModelFile(): File {
        val out = File(context.filesDir, "foot-v1.onnx")
        val assetKey = "flutter_assets/assets/models/foot-v1.onnx"
        try {
            context.assets.openFd(assetKey).use { afd ->
                if (out.exists() && out.length() == afd.length) return out
            }
        } catch (_: Exception) {
            if (out.exists()) return out
        }
        context.assets.open(assetKey).use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out
    }

    private fun runInference(nv21: ByteArray, width: Int, height: Int, rotation: Int): Map<String, Any?> {
        // 1. NV21 (sensor space) -> RGB ints.
        val rgb = nv21ToRgb(nv21, width, height)
        // 2. Rotate to upright (matches ML Kit InputImage upright space).
        val (upright, uw, uh) = rotateUpright(rgb, width, height, rotation)
        // 3. Cover letterbox to 640 on #808080 (portal parity).
        val size = 640
        val scale = max(size / uw.toFloat(), size / uh.toFloat())
        val dw = uw * scale
        val dh = uh * scale
        val dx = (size - dw) / 2f
        val dy = (size - dh) / 2f
        val input = FloatArray(3 * size * size)
        for (y in 0 until size) {
            for (x in 0 until size) {
                val sx = ((x - dx) / scale).toInt()
                val sy = ((y - dy) / scale).toInt()
                var r = 128; var g = 128; var b = 128
                if (sx in 0 until uw && sy in 0 until uh) {
                    val px = upright[sy * uw + sx]
                    r = (px shr 16) and 0xFF
                    g = (px shr 8) and 0xFF
                    b = px and 0xFF
                }
                val i = y * size + x
                input[i] = r / 255f
                input[size * size + i] = g / 255f
                input[2 * size * size + i] = b / 255f
            }
        }
        // 4. Inference — all inside one `lock` hold: `close`/`unregister` take
        // the same lock, so the session and env cannot be destroyed under a
        // running `sess.run` (use-after-close segfaults the same way an
        // overlapped run does). The `inFlight` drop above is what keeps this
        // hold from queueing callers behind a 150 ms inference.
        synchronized(lock) {
            val sess = ensureSessionLocked()
            val buf = FloatBuffer.wrap(input)
            val tensor = ai.onnxruntime.OnnxTensor.createTensor(
                env!!, buf, longArrayOf(1, 3, size.toLong(), size.toLong()),
            )
            tensor.use {
                sess.run(mapOf("images" to it)).use { results ->
                    val first = results[0].value
                    @Suppress("UNCHECKED_CAST")
                    val arr = first as Array<Array<FloatArray>>
                    return decode(arr[0], size, dw, dh, scale, uw, uh)
                }
            }
        }
    }

    /** Port of `decodeOnnxProposals` + the worker's [1,11,N] unpack order. */
    private fun decode(
        ch: Array<FloatArray>, size: Int, dw: Float, dh: Float,
        scale: Float, bw: Int, bh: Int,
    ): Map<String, Any?> {
        val n = ch[0].size
        data class Cand(
            val cx: Float, val cy: Float, val w: Float, val h: Float,
            val hx: Float, val hy: Float, val hc: Float,
            val tx: Float, val ty: Float, val tc: Float, val conf: Float,
        )
        val kept = mutableListOf<Cand>()
        for (i in 0 until n) {
            val conf = ch[4][i]
            if (!(conf >= 0.35f)) continue
            val cx = ch[0][i]; val cy = ch[1][i]; val w = ch[2][i]; val h = ch[3][i]
            if (!cx.isFinite() || !cy.isFinite() || !w.isFinite() || !h.isFinite()) continue
            val rawHx = ch[5][i] / size; val rawHy = ch[6][i] / size
            val hc = ch[7][i]
            val rawTx = ch[8][i] / size; val rawTy = ch[9][i] / size
            val tc = ch[10][i]
            if (!(hc >= 0.3f) || !(tc >= 0.3f)) continue
            if (!rawHx.isFinite() || !rawHy.isFinite() || !rawTx.isFinite() || !rawTy.isFinite()) continue
            // Invert the cover letterbox into source-frame UV.
            fun toU(px: Float, py: Float): Pair<Float, Float> {
                val lx = px * size
                val ly = py * size
                val sx = (lx - (size - dw) / 2f) / scale / bw
                val sy = (ly - (size - dh) / 2f) / scale / bh
                return sx to sy
            }
            val (hx, hy) = toU(rawHx, rawHy)
            val (tx, ty) = toU(rawTx, rawTy)
            val cxn = cx / size; val cyn = cy / size; val wn = w / size; val hn = h / size
            kept.add(Cand(cxn, cyn, wn, hn, hx, hy, hc, tx, ty, tc, conf))
        }
        kept.sortByDescending { it.conf }
        fun iou(a: Cand, b: Cand): Float {
            val x1 = maxOf(a.cx - a.w / 2, b.cx - b.w / 2)
            val y1 = maxOf(a.cy - a.h / 2, b.cy - b.h / 2)
            val x2 = minOf(a.cx + a.w / 2, b.cx + b.w / 2)
            val y2 = minOf(a.cy + a.h / 2, b.cy + b.h / 2)
            val inter = maxOf(0f, x2 - x1) * maxOf(0f, y2 - y1)
            val union = a.w * a.h + b.w * b.h - inter
            if (!(union > 0)) return 0f
            return inter / union
        }
        val picked = mutableListOf<Cand>()
        for (c in kept) {
            if (picked.any { iou(it, c) > 0.45f }) continue
            picked.add(c)
            if (picked.size >= 2) break
        }
        if (picked.isEmpty()) return mapOf("found" to false)
        val best = picked[0]
        fun clamp01(v: Float) = v.coerceIn(0f, 1f).toDouble()
        return mapOf(
            "found" to true,
            "side" to "left",
            "score" to best.conf.toDouble(),
            "heel" to mapOf("x" to clamp01(best.hx), "y" to clamp01(best.hy), "score" to best.hc.toDouble()),
            "toe" to mapOf("x" to clamp01(best.tx), "y" to clamp01(best.ty), "score" to best.tc.toDouble()),
            "box" to mapOf(
                "x" to clamp01(best.cx / size),
                "y" to clamp01(best.cy / size),
                "w" to clamp01(best.w / size),
                "h" to clamp01(best.h / size),
            ),
        )
    }

    private fun nv21ToRgb(nv21: ByteArray, width: Int, height: Int): IntArray {
        val out = IntArray(width * height)
        val frameSize = width * height
        var i = 0
        for (y in 0 until height) {
            val uvRow = (y shr 1) * width
            for (x in 0 until width) {
                val yVal = (nv21[y * width + x].toInt() and 0xFF)
                val uvPos = frameSize + uvRow + (x and 0xFFFFFFFE.toInt())
                val v = (nv21[uvPos].toInt() and 0xFF)
                val u = (nv21[uvPos + 1].toInt() and 0xFF)
                var r = (yVal + 1.402f * (v - 128)).toInt()
                var g = (yVal - 0.344136f * (u - 128) - 0.714136f * (v - 128)).toInt()
                var b = (yVal + 1.772f * (u - 128)).toInt()
                r = r.coerceIn(0, 255); g = g.coerceIn(0, 255); b = b.coerceIn(0, 255)
                out[i++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return out
    }

    private fun rotateUpright(rgb: IntArray, w: Int, h: Int, rotation: Int): Triple<IntArray, Int, Int> {
        return when ((rotation % 360 + 360) % 360) {
            90 -> {
                val out = IntArray(rgb.size)
                for (y in 0 until h) for (x in 0 until w) out[x * h + (h - 1 - y)] = rgb[y * w + x]
                Triple(out, h, w)
            }
            180 -> {
                val out = IntArray(rgb.size)
                for (y in 0 until h) for (x in 0 until w) out[(h - 1 - y) * w + (w - 1 - x)] = rgb[y * w + x]
                Triple(out, w, h)
            }
            270 -> {
                val out = IntArray(rgb.size)
                for (y in 0 until h) for (x in 0 until w) out[(w - 1 - x) * h + y] = rgb[y * w + x]
                Triple(out, h, w)
            }
            else -> Triple(rgb, w, h)
        }
    }
}
