import 'package:meta/meta.dart';

import 'ble_status.dart';

enum BleEvent {
  /// Host BLE radio / permission status changed.
  status,

  /// iOS restored peripherals after a Bluetooth process relaunch.
  restored,
}

@immutable
class BleStatusEvent {
  const BleStatusEvent({
    required this.status,
    this.event = BleEvent.status,
    this.restoredDeviceIds = const [],
  });

  const BleStatusEvent.status(this.status)
      : event = BleEvent.status,
        restoredDeviceIds = const [];

  const BleStatusEvent.restored(
    this.status,
    this.restoredDeviceIds,
  ) : event = BleEvent.restored;

  final BleStatus status;
  final BleEvent event;
  final List<String> restoredDeviceIds;

  bool get isRestored => event == BleEvent.restored;

  @override
  String toString() =>
      'BleStatusEvent(status: $status, event: $event, restoredDeviceIds: $restoredDeviceIds)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleStatusEvent &&
          status == other.status &&
          event == other.event &&
          _listEquals(restoredDeviceIds, other.restoredDeviceIds);

  @override
  int get hashCode =>
      Object.hash(status, event, Object.hashAll(restoredDeviceIds));

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
