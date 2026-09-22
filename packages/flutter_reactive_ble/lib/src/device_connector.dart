import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_reactive_ble/src/device_scanner.dart';
import 'package:flutter_reactive_ble/src/rx_ext/repeater.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

abstract class DeviceConnector {
  Stream<ConnectionStateUpdate> get deviceConnectionStateUpdateStream;

  Stream<ConnectionStateUpdate> connect({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  });

  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  });
}

class DeviceConnectorImpl implements DeviceConnector {
  const DeviceConnectorImpl({
    required ReactiveBlePlatform blePlatform,
    required bool Function(
            {required String deviceId, required Duration cacheValidity})
        deviceIsDiscoveredRecently,
    required DeviceScanner deviceScanner,
    required Duration delayAfterScanFailure,
  })  : _deviceIsDiscoveredRecently = deviceIsDiscoveredRecently,
        _deviceScanner = deviceScanner,
        _blePlatform = blePlatform,
        _delayAfterScanFailure = delayAfterScanFailure;

  final ReactiveBlePlatform _blePlatform;
  final bool Function({
    required String deviceId,
    required Duration cacheValidity,
  }) _deviceIsDiscoveredRecently;
  final DeviceScanner _deviceScanner;
  final Duration _delayAfterScanFailure;

  static const _scanRegistryCacheValidityPeriod = Duration(seconds: 25);

  @override
  Stream<ConnectionStateUpdate> get deviceConnectionStateUpdateStream =>
      _blePlatform.connectionUpdateStream;

  @override
  Stream<ConnectionStateUpdate> connect({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    final specificConnectedDeviceStream = deviceConnectionStateUpdateStream
        .where((update) => update.deviceId == id)
        .expand((update) =>
            update.connectionState != DeviceConnectionState.disconnected
                ? [update]
                : [update, null])
        .takeWhile((update) => update != null)
        .cast<ConnectionStateUpdate>();

    final broadcast = Repeater.broadcast(
      onListenEmitFrom: () => _blePlatform
          .connectToDevice(
            id,
            servicesWithCharacteristicsToDiscover,
            connectionTimeout,
          )
          .asyncExpand((_) => specificConnectedDeviceStream),
      onCancel: () => _blePlatform.disconnectDevice(id),
    );

    return broadcast.stream;
  }

  @override
  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    final currentScan = _deviceScanner.currentScan;
    final hasNoScan = currentScan == null;
    if (hasNoScan) {
      return _prescanAndConnect(
        id,
        servicesWithCharacteristicsToDiscover,
        connectionTimeout,
        withServices,
        prescanDuration,
      );
    }

    const deepCollection = DeepCollectionEquality();
    final compare = !deepCollection.equals(
      currentScan.withServices,
      withServices,
    );
    if (compare) {
      return Stream.value(
        ConnectionStateUpdate(
          deviceId: id,
          connectionState: DeviceConnectionState.disconnected,
          failure: const GenericFailure(
            code: ConnectionError.failedToConnect,
            message: "A scan for a different service is running",
          ),
        ),
      );
    }

    final scanTimeout = prescanDuration + const Duration(seconds: 1);
    return currentScan.future.timeout(scanTimeout).asStream().asyncExpand(
          (_) => _connectIfRecentlyDiscovered(
            id,
            servicesWithCharacteristicsToDiscover,
            connectionTimeout,
          ),
        );
  }

  Stream<ConnectionStateUpdate> _prescanAndConnect(
    String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
    List<Uuid> withServices,
    Duration prescanDuration,
  ) async* {
    final isDiscovered = _deviceIsDiscoveredRecently(
      deviceId: id,
      cacheValidity: _scanRegistryCacheValidityPeriod,
    );
    if (isDiscovered) {
      yield* connect(
        id: id,
        servicesWithCharacteristicsToDiscover:
            servicesWithCharacteristicsToDiscover,
        connectionTimeout: connectionTimeout,
      );
      return;
    }

    Stream<DiscoveredDevice> scanDevices() {
      final scanResultsController = StreamController<DiscoveredDevice>();
      final deviceScanStream = _deviceScanner.scanForDevices(
          withServices: withServices, scanMode: ScanMode.lowLatency);
      final scanResultsSubscription = deviceScanStream.listen(
        scanResultsController.add,
        onError: scanResultsController.addError,
      );

      Future<void>.delayed(prescanDuration).then<void>((_) {
        scanResultsSubscription.cancel();
        scanResultsController.close();
      });

      return scanResultsController.stream;
    }

    var targetDeviceFound = false;
    try {
      await for (final discoveredDevice in scanDevices()) {
        final isTargetDevice = discoveredDevice.id == id;
        if (isTargetDevice) {
          targetDeviceFound = true;
          break;
        }
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      await Future<void>.delayed(_delayAfterScanFailure);
      yield* _connectIfRecentlyDiscovered(
        id,
        servicesWithCharacteristicsToDiscover,
        connectionTimeout,
      );
      return;
    }

    if (targetDeviceFound) {
      yield* connect(
        id: id,
        servicesWithCharacteristicsToDiscover:
            servicesWithCharacteristicsToDiscover,
        connectionTimeout: connectionTimeout,
      );
      return;
    }

    yield ConnectionStateUpdate(
      deviceId: id,
      connectionState: DeviceConnectionState.disconnected,
      failure: const GenericFailure(
          code: ConnectionError.failedToConnect,
          message: "Device is not advertising"),
    );
  }

  Stream<ConnectionStateUpdate> _connectIfRecentlyDiscovered(
    String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  ) {
    final isDiscovered = _deviceIsDiscoveredRecently(
      deviceId: id,
      cacheValidity: _scanRegistryCacheValidityPeriod,
    );
    if (isDiscovered) {
      return connect(
        id: id,
        servicesWithCharacteristicsToDiscover:
            servicesWithCharacteristicsToDiscover,
        connectionTimeout: connectionTimeout,
      );
    }

    return Stream.value(
      ConnectionStateUpdate(
        deviceId: id,
        connectionState: DeviceConnectionState.disconnected,
        failure: const GenericFailure(
            code: ConnectionError.failedToConnect,
            message: "Device is not advertising"),
      ),
    );
  }
}
