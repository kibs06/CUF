package com.solevision.app.artryon

import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Filament
import com.google.android.filament.Material
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.MaterialProvider
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/**
 * The **V0.7 compression gate** plus what one emulator run can prove about model loading.
 *
 * The authoring guide keeps Draco / meshopt / KTX2 switched off until "can the renderer decode
 * this?" is answered, because a compressed file the loader cannot decode is a dead product
 * (architecture §2.5.1, roadmap V0.7). This test answers it on whatever Android target is
 * attached — no ARCore required, because a model load only needs Filament + gltfio.
 *
 * Three things were learned the moment this was first run on a Pixel_4 emulator (API 37), and
 * they are all recorded in `docs/RoadMap/AR_TRY_ON_SPIKE_FINDINGS.md`:
 *
 *  1. **JNI libraries need explicit initialisation.** `filament-jni` / `gltfio-jni` are loaded
 *     from the static initializers of `Filament` / `Gltfio`, and nothing in SceneView or
 *     ARSceneView touches those classes. Without `Filament.init()` + `Gltfio.init()` the first
 *     `Engine.create()` dies with `UnsatisfiedLinkError: No implementation found for
 *     Engine.nCreateBuilder`. The spike itself needs the same fix — see `ArTryOnSpikeView`.
 *  2. **Ubershaders do not work at feature level 1** (OpenGL ES 3.0 — the emulator, and any
 *     low-end device of that class): every request answers "No material with the specified
 *     requirements exists.", so *no* glTF asset loads, compressed or not. `engine_capability_report`
 *     measures this instead of assuming it, and the fixture tests skip on such a target rather
 *     than pretending to fail.
 *  3. **A material/mesh mismatch aborts the process**, not the load: handing gltfio a material
 *     whose requirements the mesh cannot satisfy (wrong parameters, missing attributes) trips
 *     `utils::PreconditionPanic` inside `AssetLoader::createAsset` → SIGABRT. Production value:
 *     the authoring checklist's material/UV requirements are a crash risk, not a style rule.
 *
 * Fixtures live in `src/androidTest/assets/` (never bundled into the app):
 *   • `placeholder_shoe.glb`         — control: uncompressed, 29,340 B
 *   • `placeholder_shoe_draco.glb`   — `KHR_draco_mesh_compression`, 7,276 B
 *   • `placeholder_shoe_meshopt.glb` — `EXT_meshopt_compression` + `KHR_mesh_quantization`, 8,708 B
 *
 * All three describe the **same shoe** (generated with `npx @gltf-transform/cli@4.5.0
 * draco|meshopt …` from the uncompressed block-out), which is what makes the bounding-box
 * assertion mean something: it proves the geometry survived decoding at the right scale
 * (heel-bottom-centre at the origin, toe along +Z, 270 mm long).
 */
@RunWith(AndroidJUnit4::class)
class GltfioDecodeTest {

    private lateinit var engine: Engine
    private lateinit var materialProvider: UbershaderProvider
    private lateinit var assetLoader: AssetLoader
    private lateinit var assets: AssetManager
    private lateinit var appContext: Context

    /**
     * Why the **control** fixture (uncompressed, no extensions) could not be loaded on this
     * target, or null when it loaded. Deciding the skip from a real load rather than from a
     * probe is deliberate: a plainly-keyed ubershader request *does* resolve at feature level 1,
     * yet the fixtures' primitives still fail, so a key-level probe would have lied.
     */
    private var controlLoadFailure: String? = null

    @Before
    fun setUp() {
        // Finding 1: these two lines are not optional, and not called by SceneView.
        Filament.init()
        Gltfio.init()

        engine = Engine.create()
        materialProvider = UbershaderProvider(engine)
        assetLoader = AssetLoader(engine, materialProvider, EntityManager.get()).apply {
            enableDiagnostics(true)
        }
        assets = InstrumentationRegistry.getInstrumentation().context.assets
        appContext = InstrumentationRegistry.getInstrumentation().targetContext

        // Finding 2, measured rather than assumed. Probe the provider key-wise *and* attempt a
        // real control load; only the second one decides whether the compression gate can be
        // judged on this target.
        val probeResolved = materialProvider.getMaterial(
            MaterialProvider.MaterialKey(),
            intArrayOf(),
            "capability-probe",
        ) != null
        controlLoadFailure = try {
            // Loaded and released on purpose: an asset left alive inside the AssetLoader makes
            // the *next* createAsset() fail (measured — the control loaded, then every fixture
            // after it came back null until this destroy was added). Production corollary:
            // swapping a model must destroy the previous asset.
            assetLoader.destroyAsset(load(CONTROL_FIXTURE))
            null
        } catch (t: Throwable) {
            t.message ?: t::class.java.simpleName
        }
        Log.i(
            TAG,
            "setup: plain ubershader key resolves=$probeResolved, control fixture load=" +
                (controlLoadFailure ?: "ok"),
        )
    }

    @After
    fun tearDown() {
        assetLoader.destroy()
        materialProvider.destroy()
        engine.destroy()
    }

    /**
     * Diagnostic, and the reason the fixture tests below may skip: records the engine's backend
     * and feature level, whether precompiled materials load (they do — this is how SceneView
     * ships its own materials), and whether the **ubershader** provider can service a request.
     * The app's production path is the ubershader one.
     */
    @Test
    fun engine_capability_report() {
        val materialNames = appContext.assets.list("materials").orEmpty().filter { it.endsWith(".filamat") }
        assertTrue("no .filamat assets — SceneView's materials are missing from the app APK", materialNames.isNotEmpty())

        val precompiled = loadPrecompiledMaterial(materialNames.first { it == "opaque_colored.filamat" })
        assertTrue("precompiled material 'opaque_colored.filamat' did not load on this engine", precompiled != null)

        Log.i(
            TAG,
            "capability report: backend=${engine.backend}, supportedFeatureLevel=" +
                "${engine.supportedFeatureLevel}, activeFeatureLevel=${engine.activeFeatureLevel}, " +
                "precompiledMaterials=ok, uncompressedFixtureLoad=" +
                (controlLoadFailure ?: "ok") + ", filamatCount=${materialNames.size}",
        )
    }

    @Test
    fun uncompressedFixture_decodes() = assertFixtureShape(
        name = CONTROL_FIXTURE,
        label = "control (uncompressed)",
    )

    @Test
    fun dracoCompressedFixture_decodes() = assertFixtureShape(
        name = "placeholder_shoe_draco.glb",
        label = "KHR_draco_mesh_compression",
    )

    @Test
    fun meshoptCompressedFixture_decodes() = assertFixtureShape(
        name = "placeholder_shoe_meshopt.glb",
        label = "EXT_meshopt_compression",
    )

    // ── helpers ─────────────────────────────────────────────────────────────

    private fun loadPrecompiledMaterial(name: String): Material? {
        val bytes = appContext.assets.open("materials/$name").use { it.readBytes() }
        val buffer = directBuffer(bytes)
        return Material.Builder().payload(buffer, bytes.size).build(engine)
    }

    private fun directBuffer(bytes: ByteArray): ByteBuffer =
        ByteBuffer.allocateDirect(bytes.size)
            .order(ByteOrder.nativeOrder())
            .apply { put(bytes); rewind() }

    /**
     * Loads a fixture, retrying a few times with a driver flush in front of each attempt.
     *
     * The retry is not padding: Filament's driver comes up on its own thread, `Engine.create()`
     * returns before it is ready, and an asset created too early fails material resolution with
     * "No material with the specified requirements exists." — the same fixture loading or failing
     * from one run to the next is what gave it away. `flushAndWait()` blocks on the driver.
     */
    private fun load(name: String): FilamentAsset {
        var lastFailure: String? = null
        repeat(LOAD_ATTEMPTS) { attempt ->
            engine.flushAndWait()
            val bytes = assets.open(name).use { it.readBytes() }
            // `createAsset` returns a platform type and yields null when the file cannot be
            // parsed — an unsupported **required** extension is the usual reason, which is
            // exactly the failure this test exists to catch.
            val asset = assetLoader.createAsset(directBuffer(bytes))
            if (asset != null) {
                // Uploads vertex/index data. Draco and meshopt are decoded on the native side
                // during load, so a pass here means the decoder ran on real bytes.
                ResourceLoader(engine).loadResources(asset)
                return asset
            }
            lastFailure = "null on attempt ${attempt + 1}"
            Thread.sleep(200L * (attempt + 1))
        }
        throw AssertionError(
            "$name: the loader refused the file after $LOAD_ATTEMPTS attempts ($lastFailure) — " +
                "either an unsupported required extension or a material it could not resolve; " +
                "see logcat for the native diagnostics",
        )
    }

    private fun assertFixtureShape(name: String, label: String) {
        assumeTrue(
            "this target cannot load even the uncompressed control fixture (" +
                "${controlLoadFailure}) at feature level ${engine.supportedFeatureLevel}, so the " +
                "compression gate stays unproven here; run this test on a real device",
            controlLoadFailure == null,
        )

        val asset = load(name)
        val renderables = asset.renderableEntities
        val halfExtent = asset.boundingBox.halfExtent
        val lengthMm = halfExtent[2] * 2000f
        val widthMm = halfExtent[0] * 2000f

        Log.i(
            TAG,
            "$label: $name → renderables=${renderables.size}, bbox ${widthMm.roundMm()} × " +
                "${(halfExtent[1] * 2000f).roundMm()} × ${lengthMm.roundMm()} mm",
        )

        assertTrue("$label: no renderable entities in $name", renderables.isNotEmpty())
        // The same shoe is in all three files: 270 mm long, ~94 mm wide (contract §2.5.1).
        assertTrue(
            "$label: length should be ~270 mm, decoded $lengthMm mm — geometry corrupted " +
                "or scaled differently by the compressor",
            abs(lengthMm - 270f) < 270f * 0.02f,
        )
        assertTrue(
            "$label: width should be ~94 mm, decoded $widthMm mm",
            abs(widthMm - 94.26f) < 94.26f * 0.05f,
        )
    }

    private fun Float.roundMm(): String = String.format("%.2f", this)

    private companion object {
        const val TAG = "GltfioDecodeTest"
        const val CONTROL_FIXTURE = "placeholder_shoe.glb"
        const val LOAD_ATTEMPTS = 3
    }
}
