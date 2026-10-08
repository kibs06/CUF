package com.solevision.app.arfoot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the camera-config choice on the JVM (`:app:testDebugUnitTest`). Whether the
 * chosen config really looks like the normal camera is a device check.
 */
class CameraConfigPickTest {

    // A tall phone screen: 1080x2400, aspect ~0.45.
    private val tallDisplay = 1080.0 / 2400.0

    /** A 16:9 stream from the main camera: the usual, zoomed-looking choice. */
    private val wide16x9 = CameraConfigShape(
        index = 0,
        textureWidth = 1920, textureHeight = 1080,
        imageWidth = 1920, imageHeight = 1080,
    )

    /** A 4:3 stream from the same camera: shows more of the width on a tall screen. */
    private val fourByThree = CameraConfigShape(
        index = 1,
        textureWidth = 1440, textureHeight = 1080,
        imageWidth = 1440, imageHeight = 1080,
    )

    @Test
    fun noCandidatesMeansNoChange() {
        assertNull(pickWidestCameraConfig(emptyList(), tallDisplay))
    }

    @Test
    fun aNonPositiveDisplayAspectMeansNoChange() {
        assertNull(pickWidestCameraConfig(listOf(wide16x9), 0.0))
    }

    @Test
    fun theFourByThreeStreamWinsOnATallScreen() {
        // The 16:9 texture shows ~25% of its width on a 0.45 display; 4:3 shows far more.
        assertEquals(1, pickWidestCameraConfig(listOf(wide16x9, fourByThree), tallDisplay))
    }

    @Test
    fun aMismatchedAspectLosesToAMatchedOneEvenIfWider() {
        // CPU image and texture disagree on aspect: the point mapping would be off.
        val mismatched = CameraConfigShape(
            index = 2,
            textureWidth = 1440, textureHeight = 1080,
            imageWidth = 1920, imageHeight = 1080,
        )
        assertEquals(
            1,
            pickWidestCameraConfig(listOf(mismatched, fourByThree), tallDisplay),
        )
    }

    @Test
    fun equalViewWidthTiesGoToTheLargerTexture() {
        val small = CameraConfigShape(
            index = 3,
            textureWidth = 640, textureHeight = 480,
            imageWidth = 640, imageHeight = 480,
        )
        val large = CameraConfigShape(
            index = 4,
            textureWidth = 1440, textureHeight = 1080,
            imageWidth = 1440, imageHeight = 1080,
        )
        assertEquals(4, pickWidestCameraConfig(listOf(small, large), 4.0 / 3.0))
    }

    @Test
    fun sameAspectIsExactForNonDivisibleSizes() {
        val exact = CameraConfigShape(0, 1280, 720, 640, 360)
        assertTrue(sameAspect(exact))
        val off = CameraConfigShape(0, 1280, 720, 641, 360)
        assertFalse(sameAspect(off))
    }

    @Test
    fun visibleFractionIsOneWhenAspectsMatchTheDisplay() {
        assertEquals(1.0, visibleFraction(0.5, 0.5), 1e-9)
    }
}
