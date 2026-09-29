package com.signify.hue.flutterreactiveble.channelhandlers

import io.flutter.plugin.common.EventChannel

/// iOS-only state restoration. Android has no CBCentralManager restore.
class RestoredDevicesHandler : EventChannel.StreamHandler {
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        // No-op: restoration is not applicable on Android.
    }

    override fun onCancel(arguments: Any?) {
        // No-op
    }
}
