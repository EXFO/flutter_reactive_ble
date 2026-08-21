package com.signify.hue.flutterreactiveble.utils

import com.polidea.rxandroidble2.exceptions.BleAlreadyConnectedException
import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.signify.hue.flutterreactiveble.model.ConnectionErrorType

private val statusInMessageRegex = Regex("""status\s*[=:]?\s*(\d+)""", RegexOption.IGNORE_CASE)

fun Throwable.findCause(predicate: (Throwable) -> Boolean): Throwable? {
    var current: Throwable? = this
    while (current != null) {
        if (predicate(current)) {
            return current
        }
        current = current.cause
    }
    return null
}

fun errorTypeFromStatus(status: Int): ConnectionErrorType =
    when (status) {
        1 -> ConnectionErrorType.FAILEDTOCONNECT
        8 -> ConnectionErrorType.TIMEOUT
        19 -> ConnectionErrorType.TERMINATE_PEER_USER
        else -> ConnectionErrorType.UNKNOWN
    }

fun Throwable.errorType(): ConnectionErrorType {
    findCause { it is BleDisconnectedException }
        ?.let { return errorTypeFromStatus((it as BleDisconnectedException).state) }

    var current: Throwable? = this
    while (current != null) {
        errorTypeFromMessage(current.message.orEmpty())?.let { return it }
        current = current.cause
    }

    return ConnectionErrorType.UNKNOWN
}

fun mapDiscoverServicesError(
    throwable: Throwable,
    deviceId: String,
): Pair<String, String> {
    val alreadyConnected =
        throwable.findCause {
            it is BleAlreadyConnectedException ||
                it.message.orEmpty().contains("Already connected", ignoreCase = true)
        }

    if (alreadyConnected != null) {
        val msg = alreadyConnected.message.orEmpty()
        return "device_already_connected" to
            "Device $deviceId is already connected at the OS level but is no longer tracked " +
            "by the plugin. Call disconnectDevice (or restart Bluetooth) before retrying. " +
            "Original error: $msg"
    }

    val msg = throwable.message.orEmpty()
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

fun errorTypeFromMessage(message: String): ConnectionErrorType? {
    val status = statusInMessageRegex.find(message)?.groupValues?.getOrNull(1)?.toIntOrNull()
        ?: return null
    return errorTypeFromStatus(status)
}
