import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_reactive_ble/src/connected_device_operation.dart';
import 'package:flutter_reactive_ble/src/device_connector.dart';
import 'package:flutter_reactive_ble/src/device_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

import 'resolve_single_test.mocks.dart';

@GenerateMocks([
  ReactiveBlePlatform,
  Logger,
  ConnectedDeviceOperation,
  DeviceConnector,
  DeviceScanner,
])
void main() {
  group('resolveSingle', () {
    const deviceId = 'device-1';
    final serviceId = Uuid.parse('0000180a-0000-1000-8000-00805f9b34fb');
    final characteristicId = Uuid.parse('00002a29-0000-1000-8000-00805f9b34fb');
    final qualified = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: serviceId,
      characteristicId: characteristicId,
    );

    late MockReactiveBlePlatform blePlatform;
    late MockDeviceScanner deviceScanner;
    late MockDeviceConnector deviceConnector;
    late MockConnectedDeviceOperation deviceOperation;
    late FlutterReactiveBle sut;

    DiscoveredService matchingService({String serviceInstanceId = '11', String charInstanceId = '101'}) =>
        DiscoveredService(
          serviceId: serviceId,
          serviceInstanceId: serviceInstanceId,
          characteristicIds: [characteristicId],
          includedServices: [],
          characteristics: [
            DiscoveredCharacteristic(
              characteristicId: characteristicId,
              characteristicInstanceId: charInstanceId,
              serviceId: serviceId,
              isReadable: true,
              isWritableWithResponse: true,
              isWritableWithoutResponse: true,
              isNotifiable: true,
              isIndicatable: true,
            ),
          ],
        );

    setUp(() {
      blePlatform = MockReactiveBlePlatform();
      deviceScanner = MockDeviceScanner();
      deviceConnector = MockDeviceConnector();
      deviceOperation = MockConnectedDeviceOperation();

      when(blePlatform.initialize()).thenAnswer((_) async {});
      when(blePlatform.deinitialize()).thenAnswer((_) async {});
      when(blePlatform.bleStatusStream).thenAnswer((_) => const Stream.empty());
      when(deviceConnector.deviceConnectionStateUpdateStream)
          .thenAnswer((_) => const Stream.empty());

      sut = FlutterReactiveBle.withDependencies(
        reactiveBlePlatform: blePlatform,
        deviceScanner: deviceScanner,
        deviceConnector: deviceConnector,
        connectedDeviceOperation: deviceOperation,
        debugLogger: MockLogger(),
        initialization: Future.value(),
      );
    });

    tearDown(() async {
      await sut.deinitialize();
    });

    test('returns characteristic when exactly one match', () async {
      when(deviceOperation.getDiscoverServices(deviceId))
          .thenAnswer((_) async => [matchingService()]);

      final characteristic = await sut.resolveSingle(qualified);

      expect(characteristic.id, characteristicId);
      expect(characteristic.service.id, serviceId);
    });

    test('throws notFound for empty match', () async {
      when(deviceOperation.getDiscoverServices(deviceId)).thenAnswer((_) async => []);

      await expectLater(
        sut.resolveSingle(qualified),
        throwsA(isA<CharacteristicNotFoundException>()),
      );
    });

    test('throws ambiguous when multiple matches', () async {
      when(deviceOperation.getDiscoverServices(deviceId)).thenAnswer(
        (_) async => [
          matchingService(),
          matchingService(serviceInstanceId: '12', charInstanceId: '102'),
        ],
      );

      await expectLater(
        sut.resolveSingle(qualified),
        throwsA(
          isA<AmbiguousCharacteristicException>().having(
            (e) => e.matchCount,
            'matchCount',
            2,
          ),
        ),
      );
    });

    test('maps discovery failure to connectionLost', () async {
      when(deviceOperation.getDiscoverServices(deviceId))
          .thenThrow(Exception('Device is not connected'));

      await expectLater(
        sut.resolveSingle(qualified),
        throwsA(
          isA<CharacteristicConnectionLostException>().having(
            (e) => e.cause.toString(),
            'cause',
            contains('Device is not connected'),
          ),
        ),
      );
    });
  });
}
