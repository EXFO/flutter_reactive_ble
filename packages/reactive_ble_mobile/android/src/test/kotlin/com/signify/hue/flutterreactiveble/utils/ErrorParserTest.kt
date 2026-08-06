package com.signify.hue.flutterreactiveble.utils

import com.google.common.truth.Truth.assertThat
import com.polidea.rxandroidble2.exceptions.BleAlreadyConnectedException
import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.signify.hue.flutterreactiveble.model.ConnectionErrorType
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

@DisplayName("ErrorParser unit tests")
class ErrorParserTest {
    @Nested
    @DisplayName("errorType")
    inner class ErrorTypeTest {
        @Test
        @DisplayName("Maps GATT status 8 to TIMEOUT")
        fun mapsStatusEightToTimeout() {
            val error = BleDisconnectedException("AA:BB:CC:DD:EE:FF", 8)

            assertThat(error.errorType()).isEqualTo(ConnectionErrorType.TIMEOUT)
        }

        @Test
        @DisplayName("Maps GATT status 19 to TERMINATE_PEER_USER")
        fun mapsStatusNineteenToTerminatePeerUser() {
            val error = BleDisconnectedException("AA:BB:CC:DD:EE:FF", 19)

            assertThat(error.errorType()).isEqualTo(ConnectionErrorType.TERMINATE_PEER_USER)
        }

        @Test
        @DisplayName("Maps GATT status 1 to FAILEDTOCONNECT")
        fun mapsStatusOneToFailedToConnect() {
            val error = BleDisconnectedException("AA:BB:CC:DD:EE:FF", 1)

            assertThat(error.errorType()).isEqualTo(ConnectionErrorType.FAILEDTOCONNECT)
        }

        @Test
        @DisplayName("Maps wrapped BleDisconnectedException cause to TIMEOUT")
        fun mapsWrappedCauseToTimeout() {
            val cause = BleDisconnectedException("AA:BB:CC:DD:EE:FF", 8)
            val error = Exception("wrapper", cause)

            assertThat(error.errorType()).isEqualTo(ConnectionErrorType.TIMEOUT)
        }

        @Test
        @DisplayName("Maps wrapped status 8 message to TIMEOUT")
        fun mapsWrappedStatusEightMessageToTimeout() {
            val error =
                Exception(
                    "Disconnected from MAC='AA:BB:CC:DD:EE:FF' with status 8 " +
                        "(GATT_INSUF_AUTHORIZATION or GATT_CONN_TIMEOUT)",
                )

            assertThat(error.errorType()).isEqualTo(ConnectionErrorType.TIMEOUT)
        }

        @Test
        @DisplayName("Maps unknown throwable to UNKNOWN")
        fun mapsUnknownThrowableToUnknown() {
            val error = IllegalStateException("boom")

            assertThat(error.errorType()).isEqualTo(ConnectionErrorType.UNKNOWN)
        }
    }

    @Nested
    @DisplayName("mapDiscoverServicesError")
    inner class MapDiscoverServicesErrorTest {
        @Test
        @DisplayName("Returns timeout code for GATT status 8")
        fun returnsTimeoutCodeForStatusEight() {
            val error =
                Exception(
                    "Disconnected from MAC='AA:BB:CC:DD:EE:FF' with status 8 " +
                        "(GATT_INSUF_AUTHORIZATION or GATT_CONN_TIMEOUT)",
                )

            val (code, message) = mapDiscoverServicesError(error, "AA:BB:CC:DD:EE:FF")

            assertThat(code).isEqualTo("service_discovery_timeout")
            assertThat(message).contains("status 8")
        }

        @Test
        @DisplayName("Returns terminated code for GATT status 19")
        fun returnsTerminatedCodeForStatusNineteen() {
            val error = BleDisconnectedException("AA:BB:CC:DD:EE:FF", 19)

            val (code, _) = mapDiscoverServicesError(error, "AA:BB:CC:DD:EE:FF")

            assertThat(code).isEqualTo("service_discovery_terminated")
        }

        @Test
        @DisplayName("Returns already-connected code for BleAlreadyConnectedException")
        fun returnsAlreadyConnectedCode() {
            val error = BleAlreadyConnectedException("AA:BB:CC:DD:EE:FF")

            val (code, message) = mapDiscoverServicesError(error, "AA:BB:CC:DD:EE:FF")

            assertThat(code).isEqualTo("device_already_connected")
            assertThat(message).contains("already connected at the OS level")
        }

        @Test
        @DisplayName("Returns generic failure code for unknown errors")
        fun returnsGenericFailureForUnknown() {
            val error = IllegalStateException("boom")

            val (code, message) = mapDiscoverServicesError(error, "AA:BB:CC:DD:EE:FF")

            assertThat(code).isEqualTo("service_discovery_failure")
            assertThat(message).contains("boom")
        }
    }
}
