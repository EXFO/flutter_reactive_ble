import CoreBluetooth

typealias RSSI = Int

typealias PeripheralID = UUID
typealias ServiceID = CBUUID
typealias ServiceInstanceID = String
typealias CharacteristicID = CBUUID
typealias CharacteristicInstanceID = String

typealias ServiceData = [ServiceID: Data]
typealias AdvertisementData = [String: Any]

final class Central {

    typealias StateChangeHandler = (Central, CBManagerState) -> Void
    typealias DiscoveryHandler = (Central, CBPeripheral, AdvertisementData, RSSI) -> Void
    typealias ConnectionChangeHandler = (Central, CBPeripheral, ConnectionChange) -> Void
    typealias RestoredStateHandler = (Central, [PeripheralID], [ServiceID]?) -> Void
    typealias ServicesWithCharacteristicsDiscoveryHandler = (Central, CBPeripheral, [Error]) -> Void
    typealias CharacteristicNotifyCompletionHandler = (Central, Error?) -> Void
    typealias CharacteristicValueUpdateHandler = (Central, CharacteristicInstance, Data?, Error?) -> Void
    typealias CharacteristicWriteCompletionHandler = (Central, CharacteristicInstance, Error?) -> Void

    private let onServicesWithCharacteristicsInitialDiscovery: ServicesWithCharacteristicsDiscoveryHandler
    private let onRestoredState: RestoredStateHandler

    private var peripheralDelegate: PeripheralDelegate!
    private var centralManagerDelegate: CentralManagerDelegate!
    private var centralManager: CBCentralManager!

    private(set) var isScanning = false
    private(set) var activePeripherals = [PeripheralID: CBPeripheral]()
    private let queueIdentifier = DispatchQueue(label: "com.signifiy.hue.flutterreactiveble.central.queue", qos: .userInitiated)
    private let queueSpecificKey = DispatchSpecificKey<UInt8>()
    private let queueSpecificValue: UInt8 = 1
    private(set) lazy var connectRegistry = PeripheralTaskRegistry<ConnectTaskController>(timeoutQueue: queueIdentifier)
    private lazy var servicesWithCharacteristicsDiscoveryRegistry = PeripheralTaskRegistry<ServicesWithCharacteristicsDiscoveryTaskController>(timeoutQueue: queueIdentifier)
    private lazy var characteristicNotifyRegistry = PeripheralTaskRegistry<CharacteristicNotifyTaskController>(timeoutQueue: queueIdentifier)
    private lazy var characteristicWriteRegistry = PeripheralTaskRegistry<CharacteristicWriteTaskController>(timeoutQueue: queueIdentifier)
    private lazy var readRssiRegistry = PeripheralTaskRegistry<ReadRssiTaskController>(timeoutQueue: queueIdentifier)
    private var reconnectIntents = [PeripheralID: ServicesWithCharacteristicsToDiscover]()
    private var manualDisconnects = Set<PeripheralID>()
    private static let restoreIdentifier = "com.signifiy.hue.flutterreactiveble.central.restoration"

    init(
        onStateChange: @escaping StateChangeHandler,
        onDiscovery: @escaping DiscoveryHandler,
        onConnectionChange: @escaping ConnectionChangeHandler,
        onRestoredState: @escaping RestoredStateHandler = { _, _, _ in },
        onServicesWithCharacteristicsInitialDiscovery: @escaping ServicesWithCharacteristicsDiscoveryHandler,
        onCharacteristicValueUpdate: @escaping CharacteristicValueUpdateHandler
    ) {
        self.onServicesWithCharacteristicsInitialDiscovery = onServicesWithCharacteristicsInitialDiscovery
        self.onRestoredState = onRestoredState
        self.queueIdentifier.setSpecific(key: queueSpecificKey, value: queueSpecificValue)
        self.centralManagerDelegate = CentralManagerDelegate(
            onStateChange: papply(weak: self) { central, state in
                if state != .poweredOn {
                    central.activePeripherals.forEach { _, peripheral in
                        let error = Failure.notPoweredOn(actualState: state)
                        central.eject(peripheral, error: error)
                        onConnectionChange(central, peripheral, .disconnected(error))
                    }
                } else {
                    central.reconnectIntents.keys.forEach { peripheralID in
                        central.tryReconnectIfNeeded(for: peripheralID)
                    }
                }
                onStateChange(central, state)
            },
            onDiscovery: papply(weak: self, onDiscovery),
            onConnectionChange: papply(weak: self) { central, peripheral, change in
                central.connectRegistry.updateTask(
                    key: peripheral.identifier,
                    action: { $0.handleConnectionChange(change) }
                )

                switch change {
                case .connected:
                    central.manualDisconnects.remove(peripheral.identifier)
                    break
                case .failedToConnect(let error), .disconnected(let error):
                    central.eject(peripheral, error: error ?? PluginError.connectionLost)
                    central.tryReconnectIfNeeded(for: peripheral.identifier)
                }

                onConnectionChange(central, peripheral, change)
            },
            onRestoreState: papply(weak: self) { central, peripherals, scanServiceUuids in
                let peripheralIds = peripherals.map(\.identifier)
                central.onRestoredState(central, peripheralIds, scanServiceUuids)
                central.handleRestoredScan(scanServiceUuids)
                central.handleRestoredPeripherals(peripherals)
                peripherals.forEach { peripheral in
                    if peripheral.state == .connected {
                        onConnectionChange(central, peripheral, .connected)
                    }
                }
            }
        )
        self.peripheralDelegate = PeripheralDelegate(
            onServicesDiscovery: papply(weak: self) { central, peripheral, error in
                central.servicesWithCharacteristicsDiscoveryRegistry.updateTask(
                    key: peripheral.identifier,
                    action: { $0.handleServicesDiscovery(peripheral: peripheral, error: error) }
                )
            },
            onCharacteristicsDiscovery: papply(weak: self) { central, service, error in
                guard let peripheral = service.peripheral else { return }
                central.servicesWithCharacteristicsDiscoveryRegistry.updateTask(
                    key: peripheral.identifier,
                    action: { $0.handleCharacteristicsDiscovery(service: service, error: error) }
                )
            },
            onCharacteristicNotificationStateUpdate: papply(weak: self) { central, characteristic, error in
                guard let q = try? CharacteristicInstance(characteristic)
                else {
                    return
                }

                central.characteristicNotifyRegistry.updateTask(
                    key: q,
                    action: { $0.complete(error: error) }
                )
            },
            onCharacteristicValueUpdate: papply(weak: self) { central, characteristic, error in
                guard let q = try? CharacteristicInstance(characteristic)
                else {
                    return
                }

                onCharacteristicValueUpdate(central, q, characteristic.value, error)
            },
            onCharacteristicValueWrite: papply(weak: self) { central, characteristic, error in
                guard let q = try? CharacteristicInstance(characteristic)
                else {
                    return
                }

                central.characteristicWriteRegistry.updateTask(
                    key: q,
                    action: { $0.handleWrite(error: error) }
                )
            },
            onReadRssi: papply(weak: self) { central, peripheral, rssi, error in
                central.readRssiRegistry.updateTask(
                    key: peripheral.identifier,
                    action: { $0.handleReadRssi(rssi: rssi, error: error) }
                )
            }
        )

        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
        ]

        self.centralManager = CBCentralManager(
            delegate: centralManagerDelegate,
            queue: queueIdentifier,
            options: options
        )
    }

    var state: CBManagerState {
        performSync {
            centralManager.state
        }
    }

    func scanForDevices(with services: [ServiceID]?) {
        performSync {
            isScanning = true
            centralManager.scanForPeripherals(
                withServices: services,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func stopScan() {
        performSync {
            centralManager.stopScan()
            isScanning = false
        }
    }

    func connect(to peripheralID: PeripheralID, discover servicesWithCharacteristicsToDiscover: ServicesWithCharacteristicsToDiscover, timeout: TimeInterval?) throws {
        try performSync {
            let peripheral = try resolve(known: peripheralID)

            peripheral.delegate = peripheralDelegate
            activePeripherals[peripheral.identifier] = peripheral

            connectRegistry.registerTask(
                key: peripheralID,
                params: .init(),
                timeout: timeout.map { timeout in (
                    duration: timeout,
                    handler: papply(weak: self) { (central: Central) -> Void in
                        central.disconnect(from: peripheralID)
                    }
                )},
                completion: papply(weak: self) { central, connectionChange in
                    switch connectionChange {
                    case .connected:
                        peripheral.delegate = central.peripheralDelegate

                        central.discoverServicesWithCharacteristics(
                            for: peripheral,
                            discover: servicesWithCharacteristicsToDiscover,
                            completion: central.onServicesWithCharacteristicsInitialDiscovery
                        )
                    case .failedToConnect, .disconnected:
                        break
                    }
                }
            )

            connectRegistry.updateTask(
                key: peripheralID,
                action: { $0.connect(centralManager: centralManager, peripheral: peripheral) }
            )
        }
    }

    func disconnect(from peripheralID: PeripheralID) {
        performSync {
            guard let peripheral = try? resolve(known: peripheralID)
            else { return }

            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    func enableAutoReconnect(for peripheralID: PeripheralID, discover servicesWithCharacteristicsToDiscover: ServicesWithCharacteristicsToDiscover) {
        performSync {
            reconnectIntents[peripheralID] = servicesWithCharacteristicsToDiscover
            manualDisconnects.remove(peripheralID)
        }
    }

    func disableAutoReconnect(for peripheralID: PeripheralID) {
        performSync {
            reconnectIntents.removeValue(forKey: peripheralID)
            manualDisconnects.insert(peripheralID)
        }
    }

    func disconnectAll() {
        performSync {
            activePeripherals
                .values
                .forEach(centralManager.cancelPeripheralConnection)
        }
    }

    func discoverServicesWithCharacteristics(
        for peripheralID: PeripheralID,
        discover servicesWithCharacteristicsToDiscover: ServicesWithCharacteristicsToDiscover,
        completion: @escaping ServicesWithCharacteristicsDiscoveryHandler
    ) throws {
        try performSync {
            let peripheral = try resolve(connected: peripheralID)

            discoverServicesWithCharacteristics(
                for: peripheral,
                discover: servicesWithCharacteristicsToDiscover,
                completion: completion
            )
        }
    }

    func peripheral(for peripheralID: PeripheralID) throws -> CBPeripheral {
        try performSync {
            try resolve(connected: peripheralID)
        }
    }

    private func discoverServicesWithCharacteristics(
        for peripheral: CBPeripheral,
        discover servicesWithCharacteristicsToDiscover: ServicesWithCharacteristicsToDiscover,
        completion: @escaping ServicesWithCharacteristicsDiscoveryHandler
    ) {
        servicesWithCharacteristicsDiscoveryRegistry.registerTask(
            key: peripheral.identifier,
            params: .init(servicesWithCharacteristicsToDiscover: servicesWithCharacteristicsToDiscover),
            completion: papply(weak: self) { central, result in
                completion(central, peripheral, result)
            }
        )
        servicesWithCharacteristicsDiscoveryRegistry.updateTask(
            key: peripheral.identifier,
            action: { $0.start(peripheral: peripheral) }
        )
    }

    func turnNotifications(_ state: OnOff, for characteristicInstance: CharacteristicInstance, completion: @escaping CharacteristicNotifyCompletionHandler) throws {
        try performSync {
            let characteristic = try resolve(characteristic: characteristicInstance)

            guard [CBCharacteristicProperties.notify, .notifyEncryptionRequired, .indicate, .indicateEncryptionRequired]
                    .contains(where: characteristic.properties.contains)
            else { throw Failure.notificationsNotSupported(characteristicInstance) }

            characteristicNotifyRegistry.registerTask(
                key: characteristicInstance,
                params: .init(state: state),
                completion: papply(weak: self) { central, result in
                    completion(central, result)
                }
            )

            characteristicNotifyRegistry.updateTask(
                key: characteristicInstance,
                action: { $0.start(characteristic: characteristic) }
            )
        }
    }

    func read(characteristic characteristicInstance: CharacteristicInstance) throws {
        try performSync {
            let characteristic = try resolve(characteristic: characteristicInstance)

            guard characteristic.properties.contains(.read)
            else { throw Failure.notReadable(characteristicInstance) }

            guard let peripheral = characteristic.service?.peripheral
            else { throw Failure.peripheralIsUnknown(characteristicInstance.peripheralID) }

            peripheral.readValue(for: characteristic)
        }
    }

    func writeWithResponse(
        value: Data,
        characteristic characteristicInstance: CharacteristicInstance,
        completion: @escaping CharacteristicWriteCompletionHandler
    ) throws {
        try performSync {
            let characteristic = try resolve(characteristic: characteristicInstance)

            guard characteristic.properties.contains(.write)
            else { throw Failure.notWritable(characteristicInstance) }

            let qualifiedChar = try CharacteristicInstance(characteristic)

            characteristicWriteRegistry.registerTask(
                key: qualifiedChar,
                params: .init(value: value),
                completion: papply(weak: self) { central, error in
                    completion(central, qualifiedChar, error)
                }
            )

            guard let peripheral = characteristic.service?.peripheral
            else { throw Failure.peripheralIsUnknown(qualifiedChar.peripheralID) }

            characteristicWriteRegistry.updateTask(
                key: qualifiedChar,
                action: { $0.start(peripheral: peripheral) }
            )
        }
    }

    func writeWithoutResponse(
        value: Data,
        characteristic characteristicInstance: CharacteristicInstance
    ) throws {
        try performSync {
            let characteristic = try resolve(characteristic: characteristicInstance)

            guard characteristic.properties.contains(.writeWithoutResponse)
            else { throw Failure.notWritable(characteristicInstance) }

            guard let response = characteristic.service?.peripheral?.writeValue(value, for: characteristic, type: .withoutResponse)
            else { throw Failure.characteristicNotFound(characteristicInstance) }

            return response
        }
    }

    func maximumWriteValueLength(for peripheral: PeripheralID, type: CBCharacteristicWriteType) throws -> Int {
        try performSync {
            let peripheral = try resolve(connected: peripheral)
            return peripheral.maximumWriteValueLength(for: type)
        }
    }

    func readRssi(for peripheralId: PeripheralID, completion: @escaping (Failable<Int>) -> Void) throws {
        try performSync {
            let peripheral = try resolve(connected: peripheralId)

            readRssiRegistry.registerTask(
                key: peripheralId,
                params: .init(),
                completion: completion
            )

            readRssiRegistry.updateTask(
                key: peripheralId,
                action: {
                    $0.start(peripheral: peripheral)
                }
            )
        }
    }

    func shutdown(_ completion: @escaping () -> Void) {
        queueIdentifier.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }

            self.centralManager.stopScan()
            self.isScanning = false
            self.connectRegistry.clearAll()
            self.servicesWithCharacteristicsDiscoveryRegistry.clearAll()
            self.characteristicNotifyRegistry.clearAll()
            self.characteristicWriteRegistry.clearAll()
            self.readRssiRegistry.clearAll()
            self.reconnectIntents.removeAll()
            self.manualDisconnects.removeAll()
            self.activePeripherals.values.forEach(self.centralManager.cancelPeripheralConnection)
            self.activePeripherals.removeAll()

            DispatchQueue.main.async(execute: completion)
        }
    }

    private func eject(_ peripheral: CBPeripheral, error: Error) {
        peripheral.delegate = nil
        activePeripherals[peripheral.identifier] = nil

        servicesWithCharacteristicsDiscoveryRegistry.updateTasks(
            in: peripheral.identifier,
            action: { $0.cancel(error: error) }
        )
        characteristicNotifyRegistry.updateTasks(
            in: peripheral.identifier,
            action: { $0.cancel(error: error) }
        )
        characteristicWriteRegistry.updateTasks(
            in: peripheral.identifier,
            action: { $0.cancel(error: error) }
        )
    }

    private func handleRestoredPeripherals(_ peripherals: [CBPeripheral]) {
        guard !peripherals.isEmpty else {
            return
        }

        peripherals.forEach { peripheral in
            peripheral.delegate = peripheralDelegate
            activePeripherals[peripheral.identifier] = peripheral
            tryReconnectIfNeeded(for: peripheral.identifier)
        }
    }

    private func tryReconnectIfNeeded(for peripheralID: PeripheralID) {
        guard centralManager.state == .poweredOn,
              !manualDisconnects.contains(peripheralID),
              let servicesWithCharacteristicsToDiscover = reconnectIntents[peripheralID]
        else {
            return
        }

        guard let peripheral = try? resolve(known: peripheralID),
              peripheral.state != .connected,
              peripheral.state != .connecting
        else {
            return
        }

        try? connect(
            to: peripheralID,
            discover: servicesWithCharacteristicsToDiscover,
            timeout: nil
        )
    }

    private func handleRestoredScan(_ restoredScanServices: [ServiceID]?) {
        guard let restoredScanServices = restoredScanServices else {
            return
        }

        isScanning = true
    }

    private func resolve(known peripheralID: PeripheralID) throws -> CBPeripheral {
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [peripheralID]).first
        else { throw Failure.peripheralIsUnknown(peripheralID) }

        return peripheral
    }

    private func resolve(connected peripheralID: PeripheralID) throws -> CBPeripheral {
        guard let peripheral = activePeripherals[peripheralID]
        else { throw Failure.peripheralIsUnknown(peripheralID) }

        guard peripheral.state == .connected
        else { throw Failure.peripheralIsNotConnected(peripheralID) }

        return peripheral
    }

    private func resolve(characteristic characteristicInstance: CharacteristicInstance) throws -> CBCharacteristic {
        let peripheral = try resolve(connected: characteristicInstance.peripheralID)

        let filteredServices = peripheral.services?.filter { $0.uuid == characteristicInstance.serviceID } ?? []
        let serviceIndex = Int(characteristicInstance.serviceInstanceID) ?? 0

        guard serviceIndex >= 0, serviceIndex < filteredServices.count
        else { throw Failure.serviceNotFound(characteristicInstance.serviceID, characteristicInstance.peripheralID) }

        let service = filteredServices[serviceIndex]

        let filteredCharacteristics = service.characteristics?.filter {$0.uuid == characteristicInstance.id} ?? []
        let characteristicsIndex = Int(characteristicInstance.instanceID) ?? 0

        guard characteristicsIndex >= 0, characteristicsIndex < filteredCharacteristics.count
        else { throw Failure.characteristicNotFound(characteristicInstance) }

        return filteredCharacteristics[characteristicsIndex]
    }

    private func performSync<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == queueSpecificValue {
            return try operation()
        }

        return try queueIdentifier.sync(execute: operation)
    }

    private enum Failure: Error, CustomStringConvertible {

        case notPoweredOn(actualState: CBManagerState)
        case peripheralIsUnknown(PeripheralID)
        case peripheralIsNotConnected(PeripheralID)
        case serviceNotFound(ServiceID, PeripheralID)
        case characteristicNotFound(CharacteristicInstance)
        case notificationsNotSupported(CharacteristicInstance)
        case notReadable(CharacteristicInstance)
        case notWritable(CharacteristicInstance)

        var description: String {
            switch self {
            case .notPoweredOn(let actualState):
                return "Bluetooth is not powered on (the current state code is \(actualState.rawValue))"
            case .peripheralIsUnknown(let peripheralID):
                return "A peripheral \(peripheralID.uuidString) is unknown (make sure it has been discovered)"
            case .peripheralIsNotConnected(let peripheralID):
                return "The peripheral \(peripheralID.uuidString) is not connected"
            case .serviceNotFound(let serviceID, let peripheralID):
                return "A service \(serviceID) is not found in the peripheral \(peripheralID) (make sure it has been discovered)"
            case .characteristicNotFound(let characteristicInstance):
                return "A characteristic \(characteristicInstance.id) is not found in the service \(characteristicInstance.serviceID) of the peripheral \(characteristicInstance.peripheralID) (make sure it has been discovered)"
            case .notificationsNotSupported(let characteristicInstance):
                return "The characteristic \(characteristicInstance.id) of the service \(characteristicInstance.serviceID) of the peripheral \(characteristicInstance.peripheralID) does not support either notifications or indications"
            case .notReadable(let characteristicInstance):
                return "The characteristic \(characteristicInstance.id) of the service \(characteristicInstance.serviceID) of the peripheral \(characteristicInstance.peripheralID) is not readable"
            case .notWritable(let characteristicInstance):
                return "The characteristic \(characteristicInstance.id) of the service \(characteristicInstance.serviceID) of the peripheral \(characteristicInstance.peripheralID) is not writable"
            }
        }
    }
}
