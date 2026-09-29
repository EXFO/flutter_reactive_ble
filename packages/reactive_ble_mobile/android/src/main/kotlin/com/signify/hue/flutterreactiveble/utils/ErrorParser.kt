package com.signify.hue.flutterreactiveble.utils

import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.signify.hue.flutterreactiveble.model.ConnectionErrorType

/**
 * Stable mapping based on typed RxAndroidBle state / [TimeoutException].
 * Avoids fragile BLE error-message parsing.
 */
fun Throwable.errorType(): ConnectionErrorType {
    if (this is java.util.concurrent.TimeoutException) {
        return ConnectionErrorType.TIMEOUT
    }
    val state = (this as? BleDisconnectedException)?.state
    return when (state) {
        1 -> ConnectionErrorType.FAILEDTOCONNECT
        8 -> ConnectionErrorType.TIMEOUT
        19 -> ConnectionErrorType.DISCONNECT_FROM_USER
        else -> ConnectionErrorType.UNKNOWN
    }
}
