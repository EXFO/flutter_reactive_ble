package com.signify.hue.flutterreactiveble.channelhandlers

import com.signify.hue.flutterreactiveble.utils.BleLogger
import io.flutter.plugin.common.EventChannel

class LogHandler : EventChannel.StreamHandler {
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        BleLogger.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        BleLogger.eventSink = null
    }
}
