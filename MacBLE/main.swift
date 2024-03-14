import Foundation
import CoreBluetooth

class BLEScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var discoveredPeripherals: Set<CBPeripheral> = Set()
    var connectedPeripheral: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?
    var readCharacteristic: CBCharacteristic?
    var hexValuesToWrite: [String] = []
    var selectedCharacteristic: CBCharacteristic?
    var isWritingInProgress = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            print("Scanning for BLE devices...")

            // Schedule a timer to stop scanning after 5 seconds
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                self.centralManager.stopScan()
                self.promptForDeviceSelection()
            }
        } else {
            print("Bluetooth is not powered on or available.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else {
            // Skip peripherals with unknown names
            return
        }

        // Add discovered peripheral to the set
        discoveredPeripherals.insert(peripheral)

        let jsonString = jsonStringForPeripheral(peripheral, rssi: RSSI)
        print("----------")
        print(jsonString)
    }

    private func jsonStringForPeripheral(_ peripheral: CBPeripheral, rssi: NSNumber) -> String {
        let result: [String: Any] = [
            "name": peripheral.name ?? "Unknown",
            "UUID": peripheral.identifier.uuidString,
            "RSSI": rssi
            // Add other data if needed
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: []),
            let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        } else {
            return ""
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        connectedPeripheral = peripheral

        // Set the peripheral's delegate to self and initiate the discovery of all services
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(peripheral.name ?? "Unknown"), Error: \(error?.localizedDescription ?? "Unknown error")")
    }

    func connectPeripheral(_ peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
    }

    func disconnectPeripheral(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        if let services = peripheral.services {
            print("Discovered services for \(peripheral.name ?? "Unknown"):")
            for service in services {
                print("Service: \(service.uuid)")

                // Discover characteristics for each service
                peripheral.discoverCharacteristics(nil, for: service)
            }
        } else {
            print("No services discovered for \(peripheral.name ?? "Unknown")")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        if let characteristics = service.characteristics {
            print("Discovered characteristics for service \(service.uuid):")
            for characteristic in characteristics {
                print("Characteristic: \(characteristic.uuid)")

                if characteristic.uuid == CBUUID(string: "49535343-1E4D-4BD9-BA61-23C647249616") {
                    // Save the reference to the read characteristic and enable notifications
                    readCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        } else {
            print("No characteristics discovered for service \(service.uuid)")
        }
        
        if let characteristics = service.characteristics {
            print("Discovered characteristics for service \(service.uuid):")
            for characteristic in characteristics {
                print("Characteristic: \(characteristic.uuid)")

                if characteristic.uuid == CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3") {
                    selectedCharacteristic = characteristic

                    // Example: Write hex values with delays
                    hexValuesToWrite = ["0B", "08", "00", "AA"]
                    writeHexValuesWithDelay()
                }
            }
        } else {
            print("No characteristics discovered for service \(service.uuid)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value for characteristic: \(characteristic.uuid), Error: \(error.localizedDescription)")
            return
        }

        if let value = characteristic.value {
            // Process the received value
            processReceivedValue(value)
        }
    }

    func processReceivedValue(_ value: Data) {
        // Example: Convert the received data to a string
        print("Received value from characteristic:")
            value.forEach { byte in
                print(String(format: "%02X", byte), terminator: " ")
            }
            print()
    }

    func writeHexValuesWithDelay() {
        // Check if writing is already in progress
        guard let hexValue = hexValuesToWrite.first, !isWritingInProgress else {
            print("All hex values written.")
            return
        }

        isWritingInProgress = true

        if let dataToSend = dataFromHexString(hexValue) {
            connectedPeripheral?.writeValue(dataToSend, for: selectedCharacteristic!, type: .withResponse)
            print("Wrote hex value \(hexValue) to characteristic.")
        }

        hexValuesToWrite.removeFirst()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("Delay is over. Continuing with the next operation.")
            self.isWritingInProgress = false
            self.writeHexValuesWithDelay()
        }
    }

    func dataFromHexString(_ hexString: String) -> Data? {
        var hex = hexString
        var data = Data()

        while !hex.isEmpty {
            let index = hex.index(hex.startIndex, offsetBy: 2)
            let byte = hex[..<index]
            hex = String(hex[index...])

            if var num = UInt8(byte, radix: 16) {
                data.append(&num, count: 1)
            } else {
                // Invalid hex string
                return nil
            }
        }

        return data
    }

    func promptForDeviceSelection() {
        // Implement your logic to prompt the user for device selection here
        print("Select a device to connect:")
        for (index, peripheral) in discoveredPeripherals.enumerated() {
            print("\(index + 1). \(peripheral.name ?? "Unknown") (\(peripheral.identifier.uuidString))")
        }

        // Assuming you have a method to get user input (e.g., from console or UI)
        // You can replace this with your actual user input handling
        if let userInput = getUserInput() {
            // Assuming userInput is the index selected by the user
            let selectedIndex = userInput - 1

            // Ensure the selected index is valid
            if selectedIndex >= 0 && selectedIndex < discoveredPeripherals.count {
                let selectedPeripheral = discoveredPeripherals[discoveredPeripherals.index(discoveredPeripherals.startIndex, offsetBy: selectedIndex)]

                // Connect to the selected peripheral
                connectPeripheral(selectedPeripheral)
            } else {
                print("Invalid selection.")
            }
        } else {
            // Handle invalid or no user input
            print("Invalid or no user input.")
        }
    }

    func getUserInput() -> Int? {
        // Placeholder for getting user input (replace with your actual implementation)
        print("Enter the number of the device you want to connect to:")
        if let userInput = readLine(), let index = Int(userInput) {
            return index
        } else {
            return nil
        }
    }
}

let bleScanner = BLEScanner()

// Keep the program running to continue scanning
RunLoop.main.run()
