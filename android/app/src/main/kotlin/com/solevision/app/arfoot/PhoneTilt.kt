package com.solevision.app.arfoot

import kotlin.math.acos

/**
 * Pure math for the phone-tilt coaching of the foot scan.
 *
 * A top-down foot capture only measures correctly when the camera looks
 * straight down at the floor. This turns the camera's rotation quaternion
 * into the angle between its optical axis and straight down, so Dart can
 * ask the user to hold the phone level.
 *
 * Kept free of Android types so it can be unit-tested on the JVM.
 */

/**
 * Angle in degrees between the camera's optical axis and straight down.
 *
 * 0 = the camera points straight down at the floor (the scan pose).
 * 90 = the camera points level with the floor.
 *
 * The camera looks along its local -Z axis. Its world-space Y component is
 * -2 * (y*z - w*x), so the cosine of the angle from straight down is
 * 2 * (y*z - w*x). The value is clamped so rounding can never make acos NaN.
 */
fun tiltFromDownDegrees(qx: Float, qy: Float, qz: Float, qw: Float): Double {
    val downComponent = 2.0 * (qy.toDouble() * qz.toDouble() - qw.toDouble() * qx.toDouble())
    val clamped = downComponent.coerceIn(-1.0, 1.0)
    return Math.toDegrees(acos(clamped))
}
