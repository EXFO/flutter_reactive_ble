#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

import class CoreBluetooth.CBUUID
import class CoreBluetooth.CBService
import enum CoreBluetooth.CBManagerState
import var CoreBluetooth.CBAdvertisementDataServiceDataKey
import var CoreBluetooth.CBAdvertisementDataServiceUUIDsKey
import var CoreBluetooth.CBAdvertisementDataManufacturerDataKey
import var CoreBluetooth.CBAdvertisementDataIsConnectable
import var CoreBluetooth.CBAdvertisementDataLocalNameKey

final class PluginController {
    private enum StreamTarget {
        case connectedDevice
        case characteristicValue
    }

    struct Scan {
        let services: [CBUUID]
    }

    private static let autoReconnectDelayInSeconds: TimeInterval = 1.5
    private static let maxBufferedEvents = 1000

    private var central: Central?

    private let eventDispatchQueue = DispatchQueue(label: "com.signify.hue.flutterreactiveble.plugin.events")
    private let reconnectDispatchQueue = DispatchQueue(label: "com.signify.hue.flutterreactiveble.plugin.reconnect")
    private let scanDispatchQueue = DispatchQueue(label: "com.signify.hue.flutterreactiveble.plugin.scan")

    private var connectedDeviceSink: EventSink?
    private var characteristicValueSink: EventSink?
    private var bufferedConnectedDeviceUpdates: [PlatformMethodResult] = []
    private var bufferedCharacteristicValueUpdates: [PlatformMethodResult] = []

    var eventSink: EventSink? {
        get {
            eventDispatchQueue.sync { connectedDeviceSink }
        }
        set {
            if let sink = newValue {
                attachSinkAndFlush(sink, to: .connectedDevice)
            } else {
                detachSink(for: .connectedDevice)
            }
        }
    }
    var characteristicValueUpdateSink: EventSink? {
        get {
            eventDispatchQueue.sync { characteristicValueSink }
        }
        set {
            if let sink = newValue {
                attachSinkAndFlush(sink, to: .characteristicValue)
            } else {
                detachSink(for: .characteristicValue)
            }
        }
    }
    var stateSink: EventSink? {
        didSet {

            DispatchQueue.main.async { [weak self] in
                self?.reportState()
            }
        }
    }

    var isEventSinkReady: Bool {
        eventDispatchQueue.sync { connectedDeviceSink != nil }
    }

    var pendingEvents: [DeviceInfo] {
        eventDispatchQueue.sync {
            bufferedConnectedDeviceUpdates.compactMap { event in
                guard case .success(let message) = event else {
                    return nil
                }
                return message as? DeviceInfo
            }
        }
    }

    private var _scan: StreamingTask<Scan>?
    private var scan: StreamingTask<Scan>? {
        get {
            scanDispatchQueue.sync { _scan }
        }
        set {
            scanDispatchQueue.sync { _scan = newValue }
        }
    }

    private var autoReconnectTargets: [PeripheralID: ServicesWithCharacteristicsToDiscover] = [:]
    private var reconnectWorkItems: [PeripheralID: DispatchWorkItem] = [:]

    private var manualDisconnects = Set<PeripheralID>()

    init() {
        ensureCentralInitialized()
    }

    func initialize(name: String, completion: @escaping PlatformMethodCompletionHandler) {
        ensureCentralInitialized()

        completion(.success(nil))
    }

    private func ensureCentralInitialized() {
        guard central == nil else {
            return
        }

        central = Central(
            onStateChange: papply(weak: self) { context, _, state in
                context.reportState(state)
            },
            onDiscovery: papply(weak: self) { context, _, peripheral, advertisementData, rssi in
                guard let sink = context.scan?.sink
                else { return }

                let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? ServiceData ?? [:]
                let serviceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
                let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
                let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()
                let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? String()
                let deviceDiscoveryMessage = DeviceScanInfo.with {
                    $0.id = peripheral.identifier.uuidString
                    $0.name = name
                    $0.rssi = Int32(rssi)
                    $0.isConnectable = IsConnectable()
                    switch isConnectable {
                    case .none:
                      $0.isConnectable.code = 0
                    case .some(let isConnectable):
                      $0.isConnectable.code = isConnectable ? 2 : 1
                    }
                    $0.serviceData = serviceData
                        .map { entry in
                            ServiceDataEntry.with {
                                $0.serviceUuid = Uuid.with { $0.data = entry.key.data }
                                $0.data = entry.value
                            }
                        }
                    $0.serviceUuids = serviceUuids.map { entry in Uuid.with { $0.data = entry.data }}
                    $0.manufacturerData = manufacturerData
                }

                sink.add(.success(deviceDiscoveryMessage))
            },
            onConnectionChange: papply(weak: self) { context, central, peripheral, change in
                let failure: (code: ConnectionFailure, message: String)?

                switch change {
                case .connected:
                    context.handleConnectedDevice(peripheral.identifier)
                    // Wait for services & characteristics to be discovered
                    return
                case .failedToConnect(let underlyingError), .disconnected(let underlyingError):
                    failure = underlyingError.map { (.failedToConnect, "\($0)") }
                }

                let message = DeviceInfo.with {
                    $0.id = peripheral.identifier.uuidString
                    $0.connectionState = encode(peripheral.state)
                    if let error = failure {
                        $0.failure = GenericFailure.with {
                            $0.code = Int32(error.code.rawValue)
                            $0.message = error.message
                        }
                    }
                }

                context.emitOrBuffer(event: message)
                context.scheduleAutoReconnectIfNeeded(for: peripheral.identifier)
            },
            onRestoredState: papply(weak: self) { context, _, peripheralIds, scanServiceUuids in
                if let scanServiceUuids = scanServiceUuids {
                    context.scan = StreamingTask(parameters: .init(services: scanServiceUuids))
                }
            },
            onServicesWithCharacteristicsInitialDiscovery: papply(weak: self) { context, central, peripheral, errors in
                let message = DeviceInfo.with {
                    $0.id = peripheral.identifier.uuidString
                    $0.connectionState = encode(peripheral.state)
                    if !errors.isEmpty {
                        $0.failure = GenericFailure.with {
                            $0.code = Int32(ConnectionFailure.unknown.rawValue)
                            $0.message = errors.map(String.init(describing:)).joined(separator: "\n")
                        }
                    }
                }

                context.emitOrBuffer(event: message)
            },
            onCharacteristicValueUpdate: papply(weak: self) { context, central, characteristic, value, error in
                let message = CharacteristicValueInfo.with {
                    $0.characteristic = CharacteristicAddress.with {
                        $0.characteristicUuid = Uuid.with { $0.data = characteristic.id.data }
                        $0.characteristicInstanceID = characteristic.instanceID
                        $0.serviceUuid = Uuid.with { $0.data = characteristic.serviceID.data }
                        $0.serviceInstanceID = characteristic.serviceInstanceID
                        $0.deviceID = characteristic.peripheralID.uuidString
                    }
                    if let value = value {
                        $0.value = value
                    }
                    if let error = error {
                        $0.failure = GenericFailure.with {
                            $0.code = Int32(CharacteristicValueUpdateFailure.unknown.rawValue)
                            $0.message = "\(error)"
                        }
                    }
                }
                context.emit(.success(message), to: .characteristicValue)
            }
        )
    }

    func deinitialize(name: String, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        central.stopScan()
        central.disconnectAll()

        self.central = nil
        self.scan = nil
        eventDispatchQueue.sync {
            connectedDeviceSink = nil
            characteristicValueSink = nil
            bufferedConnectedDeviceUpdates.removeAll()
            bufferedCharacteristicValueUpdates.removeAll()
        }
        reconnectDispatchQueue.sync {
            reconnectWorkItems.values.forEach { $0.cancel() }
            reconnectWorkItems.removeAll()
            autoReconnectTargets.removeAll()
            manualDisconnects.removeAll()
        }

        completion(.success(nil))
    }

    func scanForDevices(name: String, args: ScanForDevicesRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        // A scan may already be in progress if iOS restored one after a relaunch.
        // Stop it defensively so the freshly requested scan parameters take effect.
        if central.isScanning {
            central.stopScan()
        }

        scan = StreamingTask(parameters: .init(services: args.serviceUuids.map({ uuid in CBUUID(data: uuid.data) })))

        completion(.success(nil))
    }

    func startScanning(sink: EventSink) -> FlutterError? {
        guard let central = central
        else { return PluginError.notInitialized.asFlutterError }

        guard let scan = scan
        else { return PluginError.internalInconcictency(details: "a scanning task has not been initialized yet, but a client has subscribed").asFlutterError }

        self.scan = scan.with(sink: sink)

        if !central.isScanning {
            central.scanForDevices(with: scan.parameters.services)
        }

        return nil
    }

    func stopScanning() -> FlutterError? {
        central?.stopScan()
        return nil
    }

    func connectToDevice(name: String, args: ConnectToDeviceRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        let servicesWithCharacteristicsToDiscover: ServicesWithCharacteristicsToDiscover
        if args.hasServicesWithCharacteristicsToDiscover {
            let items = args.servicesWithCharacteristicsToDiscover.items.reduce(
                into: [ServiceID: [CharacteristicID]](), { dict, item in
                    let serviceID = CBUUID(data: item.serviceID.data)
                    let characteristicIDs = item.characteristics.map { CBUUID(data: $0.data) }

                    dict[serviceID] = characteristicIDs
                }
            )
            servicesWithCharacteristicsToDiscover = ServicesWithCharacteristicsToDiscover.some(items.mapValues(CharacteristicsToDiscover.some))
        } else {
            servicesWithCharacteristicsToDiscover = .all
        }

        let timeout = args.timeoutInMs > 0 ? TimeInterval(args.timeoutInMs) / 1000 : nil

        registerAutoReconnectIntent(
            for: deviceID,
            discover: servicesWithCharacteristicsToDiscover
        )

        completion(.success(nil))

        let connectingMessage = DeviceInfo.with {
            $0.id = args.deviceID
            $0.connectionState = encode(.connecting)
        }
        emitOrBuffer(event: connectingMessage)

        do {
            try central.connect(
                to: deviceID,
                discover: servicesWithCharacteristicsToDiscover,
                timeout: timeout
            )
        } catch {
            let message = DeviceInfo.with {
                $0.id = args.deviceID
                $0.connectionState = encode(.disconnected)
                $0.failure = GenericFailure.with {
                    $0.code = Int32(ConnectionFailure.failedToConnect.rawValue)
                    $0.message = "\(error)"
                }
            }

            emitOrBuffer(event: message)
        }
    }

    func disconnectFromDevice(name: String, args: ConnectToDeviceRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        completion(.success(nil))

        markManualDisconnect(for: deviceID)
        central.disconnect(from: deviceID)
    }

    func discoverServices(name: String, args: DiscoverServicesRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        func makeDiscoveredService(service: CBService) -> DiscoveredService {
            DiscoveredService.with {
                $0.serviceUuid = Uuid.with { $0.data = service.uuid.data }
                $0.serviceInstanceID = service.instanceId?.description ?? ""
                $0.characteristicUuids = (service.characteristics ?? []).map { characteristic in
                    Uuid.with { $0.data = characteristic.uuid.data }
                }
                $0.characteristics = (service.characteristics ?? []).map { characteristic in
                    DiscoveredCharacteristic.with {
                        $0.characteristicID = Uuid.with {$0.data = characteristic.uuid.data}
                        $0.characteristicInstanceID = characteristic.instanceId?.description ?? ""
                        if let serviceUuidData = characteristic.service?.uuid.data {
                            $0.serviceID = Uuid.with {$0.data = serviceUuidData}
                        }
                        $0.isReadable = characteristic.properties.contains(.read)
                        $0.isWritableWithResponse = characteristic.properties.contains(.write)
                        $0.isWritableWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
                        $0.isNotifiable = characteristic.properties.contains(.notify)
                        $0.isIndicatable = characteristic.properties.contains(.indicate)
                    }
                }

                $0.includedServices = (service.includedServices ?? []).map(makeDiscoveredService)
            }
        }

        do {
            try central.discoverServicesWithCharacteristics(
                for: deviceID,
                discover: .all,
                completion: { central, peripheral, errors in
                    completion(.success(DiscoverServicesInfo.with {
                        $0.deviceID = deviceID.uuidString
                        $0.services = (peripheral.services ?? []).map(makeDiscoveredService)
                    }))
                }
            )
        } catch {
            completion(.failure(PluginError.unknown(error).asFlutterError))
        }
    }

    func getDiscoveredServices(name: String, args: DiscoverServicesRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        func makeDiscoveredService(service: CBService) -> DiscoveredService {
            DiscoveredService.with {
                $0.serviceUuid = Uuid.with { $0.data = service.uuid.data }
                $0.serviceInstanceID = service.instanceId?.description ?? ""
                $0.characteristicUuids = (service.characteristics ?? []).map { characteristic in
                    Uuid.with { $0.data = characteristic.uuid.data }
                }
                $0.characteristics = (service.characteristics ?? []).map { characteristic in
                    DiscoveredCharacteristic.with {
                        $0.characteristicID = Uuid.with {$0.data = characteristic.uuid.data}
                        $0.characteristicInstanceID = characteristic.instanceId?.description ?? ""
                        if let serviceUuidData = characteristic.service?.uuid.data {
                            $0.serviceID = Uuid.with {$0.data = serviceUuidData}
                        }
                        $0.isReadable = characteristic.properties.contains(.read)
                        $0.isWritableWithResponse = characteristic.properties.contains(.write)
                        $0.isWritableWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
                        $0.isNotifiable = characteristic.properties.contains(.notify)
                        $0.isIndicatable = characteristic.properties.contains(.indicate)
                    }
                }

                $0.includedServices = (service.includedServices ?? []).map(makeDiscoveredService)
            }
        }

        do {
            let peripheral = try central.peripheral(for: deviceID)
            completion(.success(DiscoverServicesInfo.with {
                        $0.deviceID = deviceID.uuidString
                        $0.services = (peripheral.services ?? []).map(makeDiscoveredService)
                    }))

        } catch {
            completion(.failure(PluginError.unknown(error).asFlutterError))
        }
    }

    func enableCharacteristicNotifications(name: String, args: NotifyCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        do {
            try central.turnNotifications(.on, for: characteristic, completion: { _, error in
                if let error = error {
                    completion(.failure(PluginError.unknown(error).asFlutterError))
                } else {
                    completion(.success(nil))
                }
            })
        } catch {
            completion(.failure(PluginError.unknown(error).asFlutterError))
        }
    }

    func disableCharacteristicNotifications(name: String, args: NotifyNoMoreCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        do {
            try central.turnNotifications(.off, for: characteristic, completion: { _, error in
                if let error = error {
                    completion(.failure(PluginError.unknown(error).asFlutterError))
                } else {
                    completion(.success(nil))
                }
            })
        } catch {
            completion(.failure(PluginError.unknown(error).asFlutterError))
        }
    }

    func readCharacteristic(name: String, args: ReadCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        completion(.success(nil))

        do {
            try central.read(characteristic: characteristic)
        } catch {
            guard let sink = characteristicValueUpdateSink
            else { return }

            let message = CharacteristicValueInfo.with {
                $0.characteristic = args.characteristic
                $0.failure = GenericFailure.with {
                    $0.code = Int32(CharacteristicValueUpdateFailure.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }
            sink.add(.success(message))
        }
    }

    func writeCharacteristicWithResponse(name: String, args: WriteCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        do {
            try central.writeWithResponse(
                value: args.value,
                characteristic: characteristic,
                completion: { _, characteristic, error in
                    let result = WriteCharacteristicInfo.with {
                        $0.characteristic = args.characteristic
                        if let error = error {
                            $0.failure = GenericFailure.with {
                                $0.code = Int32(WriteCharacteristicFailure.unknown.rawValue)
                                $0.message = "\(error)"
                            }
                        }
                    }

                    completion(.success(result))
                }
            )
        } catch {
            let result = WriteCharacteristicInfo.with {
                $0.characteristic = args.characteristic
                $0.failure = GenericFailure.with {
                    $0.code = Int32(WriteCharacteristicFailure.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }

            completion(.success(result))
        }
    }

    func writeCharacteristicWithoutResponse(name: String, args: WriteCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        let result: WriteCharacteristicInfo
        do {
            try central.writeWithoutResponse(
                value: args.value,
                characteristic: characteristic
            )
            result = WriteCharacteristicInfo.with {
                $0.characteristic = args.characteristic
            }
        } catch {
            result = WriteCharacteristicInfo.with {
                $0.characteristic = args.characteristic
                $0.failure = GenericFailure.with {
                    $0.code = Int32(WriteCharacteristicFailure.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }
        }

        completion(.success(result))
    }

    func reportMaximumWriteValueLength(name: String, args: NegotiateMtuRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let peripheralID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "peripheral ID is required").asFlutterError))
            return
        }

        let result: NegotiateMtuInfo
        do {
            let mtu = try central.maximumWriteValueLength(for: peripheralID, type: .withoutResponse)
            result = NegotiateMtuInfo.with {
                $0.deviceID = args.deviceID
                $0.mtuSize = Int32(mtu)
            }
        } catch {
            result = NegotiateMtuInfo.with {
                $0.deviceID = args.deviceID
                $0.failure = GenericFailure.with {
                    $0.code = Int32(MaximumWriteValueLengthRetrieval.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }
        }

        completion(.success(result))
    }
    
    func readRssi(name: String, args: ReadRssiRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }
        
        guard let peripheralID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "peripheral ID is required").asFlutterError))
            return
        }

        do {
            try central.readRssi(
                for: peripheralID,
                completion: papply(weak: self) { context, result in
                    result.iif(
                        success: { rssi in
                            let result: ReadRssiResult = ReadRssiResult.with {
                                $0.rssi = Int32(rssi)
                            }
                            completion(.success(result))
                        },
                        failure: { error in
                            completion(.failure(context.makeFlutterError(error: error)))
                        }
                    )
                }
            )
        } catch let error {
            completion(.failure(makeFlutterError(error: error)))
        }
    }

    // takes an error and converts it into a Flutter error
    private func makeFlutterError(error: Error) -> FlutterError {
        if let error = error as? PluginError {
            return error.asFlutterError
        } else {
            return PluginError.unknown(error).asFlutterError
        }
    }

    private func registerAutoReconnectIntent(
        for peripheralID: PeripheralID,
        discover servicesWithCharacteristicsToDiscover: ServicesWithCharacteristicsToDiscover
    ) {
        reconnectDispatchQueue.sync {
            manualDisconnects.remove(peripheralID)
            autoReconnectTargets[peripheralID] = servicesWithCharacteristicsToDiscover
            reconnectWorkItems[peripheralID]?.cancel()
            reconnectWorkItems[peripheralID] = nil
        }
    }

    private func markManualDisconnect(for peripheralID: PeripheralID) {
        reconnectDispatchQueue.sync {
            manualDisconnects.insert(peripheralID)
            autoReconnectTargets.removeValue(forKey: peripheralID)
            reconnectWorkItems[peripheralID]?.cancel()
            reconnectWorkItems[peripheralID] = nil
        }
    }

    private func handleConnectedDevice(_ peripheralID: PeripheralID) {
        reconnectDispatchQueue.sync {
            reconnectWorkItems[peripheralID]?.cancel()
            reconnectWorkItems[peripheralID] = nil
            // A successful connection means a future disconnection should be treated
            // as recoverable unless the user explicitly asked to disconnect.
            manualDisconnects.remove(peripheralID)
        }
    }

    private func scheduleAutoReconnectIfNeeded(for peripheralID: PeripheralID) {
        let workItem: DispatchWorkItem? = reconnectDispatchQueue.sync {
            guard !manualDisconnects.contains(peripheralID),
                  autoReconnectTargets[peripheralID] != nil
            else {
                return nil
            }

            reconnectWorkItems[peripheralID]?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.attemptAutoReconnect(for: peripheralID)
            }
            reconnectWorkItems[peripheralID] = workItem
            return workItem
        }

        guard let workItem = workItem else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoReconnectDelayInSeconds, execute: workItem)
    }

    private func attemptAutoReconnect(for peripheralID: PeripheralID) {
        let discover: ServicesWithCharacteristicsToDiscover? = reconnectDispatchQueue.sync {
            reconnectWorkItems[peripheralID] = nil
            guard !manualDisconnects.contains(peripheralID) else {
                return nil
            }
            return autoReconnectTargets[peripheralID]
        }

        guard let central = central, let discover = discover else {
            return
        }

        do {
            try central.connect(
                to: peripheralID,
                discover: discover,
                timeout: nil
            )

            let message = DeviceInfo.with {
                $0.id = peripheralID.uuidString
                $0.connectionState = encode(.connecting)
            }
            emitOrBuffer(event: message)
        } catch {
            // If the peripheral is temporarily unavailable, keep trying as long as
            // the connection intent remains active and wasn't manually cancelled.
            scheduleAutoReconnectIfNeeded(for: peripheralID)
        }
    }

    func emitOrBuffer(event: DeviceInfo) {
        emit(.success(event), to: .connectedDevice)
    }

    private func emit(_ result: PlatformMethodResult, to target: StreamTarget) {
        eventDispatchQueue.async { [weak self] in
            guard let self else {
                return
            }
            guard let sink = self.getSink(for: target) else {
                self.appendToBuffer(result, for: target)
                return
            }
            sink.add(result)
        }
    }

    private func attachSinkAndFlush(_ sink: EventSink, to target: StreamTarget) {
        eventDispatchQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.setSink(sink, for: target)
            let pending = self.drainBuffer(for: target)
            guard !pending.isEmpty else {
                return
            }
            pending.forEach { sink.add($0) }
        }
    }

    private func detachSink(for target: StreamTarget) {
        eventDispatchQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.setSink(nil, for: target)
        }
    }

    // MARK: - Sink helpers
    private func getSink(for target: StreamTarget) -> EventSink? {
        switch target {
        case .connectedDevice:
            return connectedDeviceSink
        case .characteristicValue:
            return characteristicValueSink
        }
    }

    private func setSink(_ sink: EventSink?, for target: StreamTarget) {
        switch target {
        case .connectedDevice:
            connectedDeviceSink = sink
        case .characteristicValue:
            characteristicValueSink = sink
        }
    }

    // MARK: - Buffer helpers
    private func appendToBuffer(_ result: PlatformMethodResult, for target: StreamTarget) {
        switch target {
        case .connectedDevice:
            bufferedConnectedDeviceUpdates.append(result)
            trimBuffer(&bufferedConnectedDeviceUpdates, streamName: "connectedDevice")
        case .characteristicValue:
            bufferedCharacteristicValueUpdates.append(result)
            trimBuffer(&bufferedCharacteristicValueUpdates, streamName: "characteristicValue")
        }
    }

    private func trimBuffer(_ buffer: inout [PlatformMethodResult], streamName: String) {
        let overflow = buffer.count - Self.maxBufferedEvents
        guard overflow > 0 else {
            return
        }
        print(
            "reactive_ble_mobile: dropped \(overflow) oldest buffered \(streamName) event(s) " +
                "(limit \(Self.maxBufferedEvents))"
        )
        buffer.removeFirst(overflow)
    }

    private func drainBuffer(for target: StreamTarget) -> [PlatformMethodResult] {
        switch target {
        case .connectedDevice:
            let pending = bufferedConnectedDeviceUpdates
            bufferedConnectedDeviceUpdates.removeAll(keepingCapacity: true)
            return pending
        case .characteristicValue:
            let pending = bufferedCharacteristicValueUpdates
            bufferedCharacteristicValueUpdates.removeAll(keepingCapacity: true)
            return pending
        }
    }

    private func reportState(_ knownState: CBManagerState? = nil) {
        guard let sink = stateSink
        else { return }

        let stateToReport = knownState ?? central?.state ?? .unknown
        let message = BleStatusInfo.with { $0.status = encode(stateToReport) }

        sink.add(.success(message))
    }
}
