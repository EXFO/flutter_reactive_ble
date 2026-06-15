package com.signify.hue.flutterreactiveble.utils

import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.signify.hue.flutterreactiveble.model.ConnectionErrorType

/**
 * Stable mapping based on typed RxAndroidBle state.
 * No message parsing to avoid fragile string matching.
 */
fun Throwable.errorType(): ConnectionErrorType {
    val state = (this as? BleDisconnectedException)?.state
    return when (state) {
        1 -> ConnectionErrorType.FAILEDTOCONNECT
        8 -> ConnectionErrorType.TIMEOUT
        19 -> ConnectionErrorType.TERMINATE_PEER_USER
        else -> ConnectionErrorType.UNKNOWN
    }
}
