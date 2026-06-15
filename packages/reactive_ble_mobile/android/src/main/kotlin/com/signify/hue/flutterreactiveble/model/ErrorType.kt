package com.signify.hue.flutterreactiveble.model

enum class ConnectionErrorType(val code: Int) {
    UNKNOWN(0),
    FAILEDTOCONNECT(1),
    TIMEOUT(2),
    TERMINATE_PEER_USER(3),
}

enum class ClearGattCacheErrorType(val code: Int) {
    UNKNOWN(0),
}

enum class CharacteristicErrorType(val code: Int) {
    UNKNOWN(0),
}

enum class NegotiateMtuErrorType(val code: Int) {
    UNKNOWN(0),
}

enum class ScanErrorType(val code: Int) {
    UNKNOWN(0),
}
