import 'package:meta/meta.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

@immutable
abstract class CharacteristicException implements Exception {
  const CharacteristicException();

  QualifiedCharacteristic get characteristic;
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

class CharacteristicNotFoundException extends CharacteristicException {
  @override
  final QualifiedCharacteristic characteristic;

  const CharacteristicNotFoundException(this.characteristic);

  @override
  String get message =>
      'Characteristic not found or discovered: deviceId=${characteristic.deviceId}, '
      'serviceId=${characteristic.serviceId}, '
      'characteristicId=${characteristic.characteristicId}';
}

class MultipleCharacteristicException extends CharacteristicException {
  @override
  final QualifiedCharacteristic characteristic;

  const MultipleCharacteristicException(this.characteristic);

  @override
  String get message =>
      'Multiple matching characteristics for: deviceId=${characteristic.deviceId}, '
      'serviceId=${characteristic.serviceId}, '
      'characteristicId=${characteristic.characteristicId}';
}

class CharacteristicConnectionLostException extends CharacteristicException {
  @override
  final QualifiedCharacteristic characteristic;

  const CharacteristicConnectionLostException(this.characteristic);

  @override
  String get message =>
      'Connection lost or device not connected while resolving characteristic: '
      'deviceId=${characteristic.deviceId}, '
      'serviceId=${characteristic.serviceId}, '
      'characteristicId=${characteristic.characteristicId}';
}
