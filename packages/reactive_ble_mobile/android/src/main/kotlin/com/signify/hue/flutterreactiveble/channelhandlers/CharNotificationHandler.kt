package com.signify.hue.flutterreactiveble.channelhandlers

import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.signify.hue.flutterreactiveble.converters.ProtobufMessageConverter
import com.signify.hue.flutterreactiveble.converters.UuidConverter
import com.signify.hue.flutterreactiveble.utils.BleLogger
import io.flutter.plugin.common.EventChannel
import io.reactivex.android.schedulers.AndroidSchedulers
import io.reactivex.disposables.Disposable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ConcurrentHashMap
import com.signify.hue.flutterreactiveble.ProtobufModel as pb

class CharNotificationHandler(private val bleClient: com.signify.hue.flutterreactiveble.ble.BleClient) :
    EventChannel.StreamHandler {
    private val uuidConverter = UuidConverter()
    private val protobufConverter = ProtobufMessageConverter()

    companion object {
        private var charNotificationSink: EventChannel.EventSink? = null

        private val subscriptionMap: MutableMap<pb.CharacteristicAddress, Disposable> = ConcurrentHashMap()
    }

    override fun onListen(
        objectSink: Any?,
        eventSink: EventChannel.EventSink?,
    ) {
        eventSink?.let {
            charNotificationSink = eventSink
        }
    }

    override fun onCancel(objectSink: Any?) {
        unsubscribeFromAllNotifications()
    }

    fun subscribeToNotifications(
        request: pb.NotifyCharacteristicRequest,
        onSetupComplete: () -> Unit,
        onSetupError: (Throwable) -> Unit,
    ) {
        val characteristicUuid =
            uuidConverter
                .uuidFromByteArray(request.characteristic.characteristicUuid.data.toByteArray())
        val setupResultDelivered = AtomicBoolean(false)
        val subscription =
            bleClient.setupNotification(
                request.characteristic.deviceId,
                characteristicUuid,
                request.characteristic.characteristicInstanceId.toInt(),
            )
                .observeOn(AndroidSchedulers.mainThread())
                .flatMap { notificationValues ->
                    if (setupResultDelivered.compareAndSet(false, true)) {
                        onSetupComplete()
                    }
                    notificationValues
                }
                .observeOn(AndroidSchedulers.mainThread())
                .subscribe({ value ->
                    handleNotificationValue(request.characteristic, value)
                }, { error ->
                    if (setupResultDelivered.compareAndSet(false, true)) {
                        onSetupError(error)
                    }
                    when (error) {
                        is BleDisconnectedException -> {
                            subscriptionMap.remove(request.characteristic)?.dispose()
                        }
                        else -> {
                            BleLogger.error(
                                "CharNotificationHandler",
                                "NotificationError: ${error.message}",
                            )
                            handleNotificationError(request.characteristic, error)
                        }
                    }
                })
        subscriptionMap[request.characteristic] = subscription
    }

    fun unsubscribeFromNotifications(request: pb.NotifyNoMoreCharacteristicRequest) {
        subscriptionMap.remove(request.characteristic)?.dispose()
    }

    fun addSingleReadToStream(charInfo: pb.CharacteristicValueInfo) {
        handleNotificationValue(charInfo.characteristic, charInfo.value.toByteArray())
    }

    fun addSingleErrorToStream(
        subscriptionRequest: pb.CharacteristicAddress,
        error: String,
    ) {
        val convertedMsg = protobufConverter.convertCharacteristicError(subscriptionRequest, error)
        charNotificationSink?.success(convertedMsg.toByteArray())
    }

    private fun unsubscribeFromAllNotifications() {
        charNotificationSink = null
        subscriptionMap.forEach { it.value.dispose() }
    }

    private fun handleNotificationValue(
        subscriptionRequest: pb.CharacteristicAddress,
        value: ByteArray,
    ) {
        val convertedMsg = protobufConverter.convertCharacteristicInfo(subscriptionRequest, value)
        charNotificationSink?.success(convertedMsg.toByteArray())
    }

    private fun handleNotificationError(
        subscriptionRequest: pb.CharacteristicAddress,
        error: Throwable,
    ) {
        val convertedMsg =
            protobufConverter.convertCharacteristicError(subscriptionRequest, error.message ?: "")
        charNotificationSink?.success(convertedMsg.toByteArray())
    }
}
