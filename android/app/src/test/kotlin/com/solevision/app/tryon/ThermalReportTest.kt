package com.solevision.app.tryon

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * **V4.8's thermal word, pinned on the JVM** (`:app:testDebugUnitTest`).
 *
 * The mapping is one `when` whose failure mode is a screenshot that says the wrong thing: a
 * throttled phone (`severe`) read as `none` would send a device session chasing a renderer bug that
 * is the weather. [ThermalReport] is a file of its own precisely so this test needs no
 * `PowerManager`, no `Context` and no device.
 *
 * ⚠️ What this file does **not** cover: the read itself (`getCurrentThermalStatus`, API 29+,
 * guarded in `ArTryOnView`), and whether a real session heats the phone at all — both belong to the
 * V4.9 device session, whose heartbeat now carries the word this test pins.
 */
class ThermalReportTest {

    @Test
    fun everyThermalStatusHasItsWord() {
        val expected = mapOf(
            0 to "none",
            1 to "light",
            2 to "moderate",
            3 to "severe",
            4 to "critical",
            5 to "emergency",
            6 to "shutdown",
        )

        for ((status, word) in expected) {
            assertEquals("status $status", word, ThermalReport.label(status))
        }
    }

    @Test
    fun aPlatformThatCannotAnswerSaysSoRatherThanGuessing() {
        // Below API 29 there is no getter at all; inventing `none` would be a claim the platform
        // never made.
        assertEquals("n/a", ThermalReport.label(null))
    }

    @Test
    fun anUnknownValueIsStatedRatherThanMapped() {
        // A newer OEM drop may add levels; an unknown int must be visible on the line, not folded
        // into a real word.
        assertEquals("unknown(9)", ThermalReport.label(9))
        assertEquals("unknown(-1)", ThermalReport.label(-1))
    }
}
