enum BleConnectionType {
  /// [connectToAdvertisingDevice] in foreground and [connectToDevice] in background.
  auto,

  /// Connection direct.
  connectToDevice,

  /// Connection with scan.
  connectToAdvertisingDevice,
}

extension BleConnectionTypeExtension on BleConnectionType {
  BleConnectionType resolve({bool isBackground = false}) {
    switch (this) {
      case BleConnectionType.auto:
        return isBackground
            ? BleConnectionType.connectToDevice
            : BleConnectionType.connectToAdvertisingDevice;
      case BleConnectionType.connectToDevice:
      case BleConnectionType.connectToAdvertisingDevice:
        return this;
    }
  }
}
