package com.signify.hue.flutterreactiveble.utils

import com.polidea.rxandroidble2.exceptions.BleAlreadyConnectedException
import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.signify.hue.flutterreactiveble.model.ConnectionErrorType

/**
 * Mapping based on typed RxAndroidBle state when available.
 */
fun Throwable.errorType(): ConnectionErrorType {
    var current: Throwable? = this
    while (current != null) {
        val state = (current as? BleDisconnectedException)?.state
        if (state != null) {
            return when (state) {
                1 -> ConnectionErrorType.FAILEDTOCONNECT
                8 -> ConnectionErrorType.TIMEOUT
                19 -> ConnectionErrorType.TERMINATE_PEER_USER
                else -> ConnectionErrorType.UNKNOWN
            }
        }
        current = current.cause
    }

    return errorTypeFromMessage(message.orEmpty())
}

fun mapDiscoverServicesError(
    throwable: Throwable,
    deviceId: String,
): Pair<String, String> {
    val msg = throwable.message.orEmpty()
    val isAlreadyConnected =
        throwable is BleAlreadyConnectedException ||
            msg.contains("Already connected", ignoreCase = true)

    if (isAlreadyConnected) {
        return "device_already_connected" to
            "Device $deviceId is already connected at the OS level but is no longer tracked " +
            "by the plugin. Call disconnectDevice (or restart Bluetooth) before retrying. " +
            "Original error: $msg"
    }

    return when (throwable.errorType()) {
        ConnectionErrorType.TIMEOUT ->
            "service_discovery_timeout" to
                (msg.ifBlank { "GATT connection timed out during service discovery" })
        ConnectionErrorType.TERMINATE_PEER_USER ->
            "service_discovery_terminated" to
                (msg.ifBlank { "Remote peer terminated connection during service discovery" })
        ConnectionErrorType.FAILEDTOCONNECT,
        ConnectionErrorType.UNKNOWN,
        ->
            "service_discovery_failure" to throwable.toString()
    }
}

private fun errorTypeFromMessage(message: String): ConnectionErrorType {
    val statusMatch = Regex("""status[= ]+(\d+)""", RegexOption.IGNORE_CASE).find(message)
    return when (statusMatch?.groupValues?.getOrNull(1)?.toIntOrNull()) {
        1 -> ConnectionErrorType.FAILEDTOCONNECT
        8 -> ConnectionErrorType.TIMEOUT
        19 -> ConnectionErrorType.TERMINATE_PEER_USER
        else -> ConnectionErrorType.UNKNOWN
    }
}
