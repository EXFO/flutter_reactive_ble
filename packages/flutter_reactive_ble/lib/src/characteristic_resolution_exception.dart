import 'package:meta/meta.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

enum CharacteristicResolutionFailure {
  notFound,
  ambiguous,
  connectionLost,
}

@immutable
abstract class CharacteristicResolutionException implements Exception {
  const CharacteristicResolutionException();

  CharacteristicResolutionFailure get failure;
  QualifiedCharacteristic get characteristic;
  String get message;
  int? get matchCount => null;

  @override
  String toString() => '$runtimeType($failure): $message';
}

class CharacteristicNotFoundException extends CharacteristicResolutionException {
  @override
  final QualifiedCharacteristic characteristic;

  const CharacteristicNotFoundException(this.characteristic);

  @override
  CharacteristicResolutionFailure get failure => CharacteristicResolutionFailure.notFound;

  @override
  int get matchCount => 0;

  @override
  String get message =>
      'Characteristic not found or discovered: deviceId=${characteristic.deviceId}, '
      'serviceId=${characteristic.serviceId}, '
      'characteristicId=${characteristic.characteristicId}';
}

class AmbiguousCharacteristicException extends CharacteristicResolutionException {
  @override
  final QualifiedCharacteristic characteristic;
  @override
  final int matchCount;

  const AmbiguousCharacteristicException(this.characteristic, this.matchCount);

  @override
  CharacteristicResolutionFailure get failure => CharacteristicResolutionFailure.ambiguous;

  @override
  String get message =>
      'Multiple matching characteristics ($matchCount) for: deviceId=${characteristic.deviceId}, '
      'serviceId=${characteristic.serviceId}, '
      'characteristicId=${characteristic.characteristicId}';
}

class CharacteristicConnectionLostException extends CharacteristicResolutionException {
  @override
  final QualifiedCharacteristic characteristic;
  final Object? cause;

  const CharacteristicConnectionLostException(this.characteristic, {this.cause});

  @override
  CharacteristicResolutionFailure get failure => CharacteristicResolutionFailure.connectionLost;

  @override
  String get message =>
      'Connection lost or device not connected while resolving characteristic: '
      'deviceId=${characteristic.deviceId}, '
      'serviceId=${characteristic.serviceId}, '
      'characteristicId=${characteristic.characteristicId}'
      '${cause != null ? '; cause=$cause' : ''}';
}
