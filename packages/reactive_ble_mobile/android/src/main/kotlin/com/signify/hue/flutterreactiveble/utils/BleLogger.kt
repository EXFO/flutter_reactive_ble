package com.signify.hue.flutterreactiveble.utils

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

internal object BleLogger {
    @Volatile
    var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun info(
        source: String,
        message: String,
    ) = emit(source, "Info", message)

    fun warning(
        source: String,
        message: String,
    ) = emit(source, "Warning", message)

    fun error(
        source: String,
        message: String,
    ) = emit(source, "Error", message)

    private fun emit(
        source: String,
        level: String,
        message: String,
    ) {
        val sink = eventSink ?: return
        val payload =
            mapOf(
                "Level" to level,
                "Source" to source,
                "Message" to message,
            )
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink.success(payload)
        } else {
            mainHandler.post { eventSink?.success(payload) }
        }
    }
}
