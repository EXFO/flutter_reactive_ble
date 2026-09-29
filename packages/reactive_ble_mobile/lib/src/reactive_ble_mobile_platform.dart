import 'dart:async';

import 'package:flutter/services.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

import 'converter/args_to_protubuf_converter.dart';
import 'converter/protobuf_converter.dart';
import 'debug_logger.dart';

class ReactiveBleMobilePlatform extends ReactiveBlePlatform {
  ReactiveBleMobilePlatform({
    required ArgsToProtobufConverter argsToProtobufConverter,
    required ProtobufConverter protobufConverter,
    required MethodChannel bleMethodChannel,
    required Stream<List<int>> connectedDeviceChannel,
    required Stream<List<int>> charUpdateChannel,
    required Stream<List<int>> bleDeviceScanChannel,
    required Stream<List<int>> bleStatusChannel,
    Stream<dynamic>? logChannel,
    Stream<dynamic>? restoredDevicesChannel,
    Logger? logger,
  }) : _argsToProtobufConverter = argsToProtobufConverter,
       _protobufConverter = protobufConverter,
       _bleMethodChannel = bleMethodChannel,
       _connectedDeviceRawStream = connectedDeviceChannel,
       _charUpdateRawStream = charUpdateChannel,
       _bleStatusRawChannel = bleStatusChannel,
       _bleDeviceScanRawStream = bleDeviceScanChannel,
       _restoredDevicesRawStream = restoredDevicesChannel,
       _logger = logger {
    if (logChannel != null) {
      _logSubscription = logChannel.listen(
        DebugLogger.log,
        onError: (_) {},
        cancelOnError: false,
      );
    }
  }

  final ArgsToProtobufConverter _argsToProtobufConverter;
  final ProtobufConverter _protobufConverter;
  final MethodChannel _bleMethodChannel;
  final Stream<List<int>> _connectedDeviceRawStream;
  final Stream<List<int>> _charUpdateRawStream;
  final Stream<List<int>> _bleDeviceScanRawStream;
  final Stream<List<int>> _bleStatusRawChannel;
  final Stream<dynamic>? _restoredDevicesRawStream;
  final Logger? _logger;

  StreamSubscription<dynamic>? _logSubscription;
  Stream<ConnectionStateUpdate>? _connectionUpdateStream;
  Stream<CharacteristicValue>? _charValueStream;
  Stream<ScanResult>? _scanResultStream;
  Stream<BleStatus>? _rawBleStatusStream;
  Stream<List<String>>? _restoredDevicesStream;
  Stream<BleStatusEvent>? _statusStream;
  BleStatus _lastStatus = BleStatus.unknown;

  @override
  Stream<ConnectionStateUpdate> get connectionUpdateStream =>
      _connectionUpdateStream ??= _connectedDeviceRawStream
          .map(_protobufConverter.connectionStateUpdateFrom)
          .map((update) {
            switch (update.connectionState) {
              case DeviceConnectionState.connecting:
                _logger?.info('Connecting: deviceId=${update.deviceId}');
                break;
              case DeviceConnectionState.connected:
                _logger?.info('Connected: deviceId=${update.deviceId}');
                break;
              default:
                _logger?.log(
                  'Received $ConnectionStateUpdate(deviceId: ${update.deviceId}, connectionState: ${update.connectionState}, failure: ${update.failure})',
                );
                break;
            }
            return update;
          });

  @override
  Stream<List<String>> get restoredDevicesStream => _restoredDevicesStream ??=
      (_restoredDevicesRawStream ?? const Stream.empty())
          .map((event) {
            if (event is List) {
              return event.map((e) => e.toString()).toList(growable: false);
            }
            return const <String>[];
          })
          .where((ids) => ids.isNotEmpty)
          .map((ids) {
            _logger?.info('RestoredPeripherals: $ids');
            return ids;
          });

  @override
  Stream<CharacteristicValue> get charValueUpdateStream =>
      _charValueStream ??= _charUpdateRawStream
          .map(_protobufConverter.characteristicValueFrom)
          .map((update) => update);

  @override
  Stream<ScanResult> get scanStream =>
      _scanResultStream ??= _bleDeviceScanRawStream
          .map(_protobufConverter.scanResultFrom)
          .map((result) => result);

  Stream<BleStatus> get _rawBleStatus => _rawBleStatusStream ??=
      _bleStatusRawChannel.map(_protobufConverter.bleStatusFrom).map((status) {
        _lastStatus = status;
        return status;
      });

  /// Single stream: BLE restore and status updates
  @override
  Stream<BleStatusEvent> get statusStream =>
      _statusStream ??= Stream.multi((data) {
        final status = _rawBleStatus.listen((status) {
          data.add(BleStatusEvent.status(status));
        }, onError: data.addError);

        final restore = restoredDevicesStream.listen((ids) {
          data.add(BleStatusEvent.restored(_lastStatus, ids));
        }, onError: data.addError);

        data.onCancel = () async {
          await status.cancel();
          await restore.cancel();
        };
      });

  @override
  Future<void> initialize() => _bleMethodChannel.invokeMethod("initialize");

  @override
  Future<void> deinitialize() {
    _logSubscription?.cancel();
    _logSubscription = null;
    return _bleMethodChannel.invokeMethod<void>("deinitialize");
  }

  @override
  Stream<void> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
    required bool requireLocationServicesEnabled,
  }) => _bleMethodChannel
      .invokeMethod<void>(
        "scanForDevices",
        _argsToProtobufConverter
            .createScanForDevicesRequest(
              withServices: withServices,
              scanMode: scanMode,
              requireLocationServicesEnabled: requireLocationServicesEnabled,
            )
            .writeToBuffer(),
      )
      .asStream();

  @override
  Stream<void> connectToDevice(
    String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  ) => _bleMethodChannel
      .invokeMethod<void>(
        "connectToDevice",
        _argsToProtobufConverter
            .createConnectToDeviceArgs(
              id,
              servicesWithCharacteristicsToDiscover,
              connectionTimeout,
            )
            .writeToBuffer(),
      )
      .asStream();

  @override
  Future<void> disconnectDevice(String deviceId) =>
      _bleMethodChannel.invokeMethod<void>(
        "disconnectFromDevice",
        _argsToProtobufConverter
            .createDisconnectDeviceArgs(deviceId)
            .writeToBuffer(),
      );

  @override
  Stream<void> readCharacteristic(CharacteristicInstance characteristic) =>
      _bleMethodChannel
          .invokeMethod<void>(
            "readCharacteristic",
            _argsToProtobufConverter
                .createReadCharacteristicRequest(characteristic)
                .writeToBuffer(),
          )
          .asStream();

  @override
  Future<WriteCharacteristicInfo> writeCharacteristicWithResponse(
    CharacteristicInstance characteristic,
    List<int> value,
  ) async => _bleMethodChannel
      .invokeMethod<List<int>>(
        "writeCharacteristicWithResponse",
        _argsToProtobufConverter
            .createWriteCharacteristicRequest(characteristic, value)
            .writeToBuffer(),
      )
      .then((data) => _protobufConverter.writeCharacteristicInfoFrom(data!));

  @override
  Future<WriteCharacteristicInfo> writeCharacteristicWithoutResponse(
    CharacteristicInstance characteristic,
    List<int> value,
  ) async => _bleMethodChannel
      .invokeMethod<List<int>>(
        "writeCharacteristicWithoutResponse",
        _argsToProtobufConverter
            .createWriteCharacteristicRequest(characteristic, value)
            .writeToBuffer(),
      )
      .then((data) => _protobufConverter.writeCharacteristicInfoFrom(data!));

  @override
  Stream<void> subscribeToNotifications(
    CharacteristicInstance characteristic,
  ) => _bleMethodChannel
      .invokeMethod<void>(
        "readNotifications",
        _argsToProtobufConverter
            .createNotifyCharacteristicRequest(characteristic)
            .writeToBuffer(),
      )
      .asStream();

  @override
  Future<void> stopSubscribingToNotifications(
    CharacteristicInstance characteristic,
  ) => _bleMethodChannel
      .invokeMethod<void>(
        "stopNotifications",
        _argsToProtobufConverter
            .createNotifyNoMoreCharacteristicRequest(characteristic)
            .writeToBuffer(),
      )
      .catchError(
        // ignore: avoid_print
        (Object e) => print("Error unsubscribing from notifications: $e"),
      );

  @override
  Future<int> requestMtuSize(String deviceId, int? mtu) async =>
      _bleMethodChannel
          .invokeMethod<List<int>>(
            "negotiateMtuSize",
            _argsToProtobufConverter
                .createNegotiateMtuRequest(deviceId, mtu!)
                .writeToBuffer(),
          )
          .then((data) => _protobufConverter.mtuSizeFrom(data!));

  @override
  Future<ConnectionPriorityInfo> requestConnectionPriority(
    String deviceId,
    ConnectionPriority priority,
  ) => _bleMethodChannel
      .invokeMethod<List<int>>(
        "requestConnectionPriority",
        _argsToProtobufConverter
            .createChangeConnectionPrioRequest(deviceId, priority)
            .writeToBuffer(),
      )
      .then((data) => _protobufConverter.connectionPriorityInfoFrom(data!));

  @override
  Future<Result<Unit, GenericFailure<ClearGattCacheError>?>> clearGattCache(
    String deviceId,
  ) => _bleMethodChannel
      .invokeMethod<List<int>>(
        "clearGattCache",
        _argsToProtobufConverter
            .createClearGattCacheRequest(deviceId)
            .writeToBuffer(),
      )
      .then((data) => _protobufConverter.clearGattCacheResultFrom(data!));

  @override
  Future<List<DiscoveredService>> discoverServices(String deviceId) async =>
      _bleMethodChannel
          .invokeMethod<List<int>>(
            'discoverServices',
            _argsToProtobufConverter
                .createDiscoverServicesRequest(deviceId)
                .writeToBuffer(),
          )
          .then((data) => _protobufConverter.discoveredServicesFrom(data!));

  @override
  Future<List<DiscoveredService>> getDiscoverServices(String deviceId) async =>
      _bleMethodChannel
          .invokeMethod<List<int>>(
            'getDiscoveredServices',
            _argsToProtobufConverter
                .createDiscoverServicesRequest(deviceId)
                .writeToBuffer(),
          )
          .then((data) => _protobufConverter.discoveredServicesFrom(data!));

  @override
  Future<int> readRssi(String deviceId) async => _bleMethodChannel
      .invokeMethod<List<int>>(
        "readRssi",
        _argsToProtobufConverter
            .createReadRssiRequest(deviceId)
            .writeToBuffer(),
      )
      .then((data) => _protobufConverter.readRssiResultFrom(data!));
}

class ReactiveBleMobilePlatformFactory {
  const ReactiveBleMobilePlatformFactory();

  ReactiveBleMobilePlatform create({Logger? logger}) {
    const bleMethodChannel = MethodChannel("flutter_reactive_ble_method");

    const connectedDeviceChannel = EventChannel(
      "flutter_reactive_ble_connected_device",
    );
    const charEventChannel = EventChannel("flutter_reactive_ble_char_update");
    const scanEventChannel = EventChannel("flutter_reactive_ble_scan");
    const bleStatusChannel = EventChannel("flutter_reactive_ble_status");
    const logEventChannel = EventChannel("flutter_reactive_ble_log");
    const restoredEventChannel = EventChannel("flutter_reactive_ble_restored");

    return ReactiveBleMobilePlatform(
      protobufConverter: const ProtobufConverterImpl(),
      argsToProtobufConverter: const ArgsToProtobufConverterImpl(),
      bleMethodChannel: bleMethodChannel,
      connectedDeviceChannel: connectedDeviceChannel
          .receiveBroadcastStream()
          .cast<List<int>>(),
      charUpdateChannel: charEventChannel
          .receiveBroadcastStream()
          .cast<List<int>>(),
      bleDeviceScanChannel: scanEventChannel
          .receiveBroadcastStream()
          .cast<List<int>>(),
      bleStatusChannel: bleStatusChannel
          .receiveBroadcastStream()
          .cast<List<int>>(),
      logChannel: logEventChannel.receiveBroadcastStream(),
      restoredDevicesChannel: restoredEventChannel.receiveBroadcastStream(),
      logger: logger,
    );
  }
}
