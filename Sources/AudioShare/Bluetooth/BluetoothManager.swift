import CoreBluetooth
import Foundation
import IOBluetooth

enum BluetoothAddress {
    /// "2c-18-09-ed-bd-72", "2C:18:09:ED:BD:72" → "2C1809EDBD72"
    static func normalize(_ address: String) -> String {
        address.uppercased().filter(\.isHexDigit)
    }
}

/// A Classic Bluetooth device that can play audio, paired or just discovered.
struct BluetoothAudioDevice: Equatable {
    let address: String
    let name: String
    let minorClass: Int
}

/// Lists paired audio devices, discovers new ones, and pairs / connects them.
/// IOBluetooth calls back on the main run loop, so everything here stays on the main actor.
@Observable
final class BluetoothManager: NSObject {
    private(set) var discovered: [BluetoothAudioDevice] = []
    private(set) var isScanning = false

    @ObservationIgnored private var inquiry: IOBluetoothDeviceInquiry?
    @ObservationIgnored private var pairings: [IOBluetoothDevicePair] = []
    @ObservationIgnored private var pairCompletions: [String: (Bool) -> Void] = [:]
    @ObservationIgnored private var connectCompletions: [String: (Bool) -> Void] = [:]

    static var isPermissionDenied: Bool {
        CBManager.authorization == .denied || CBManager.authorization == .restricted
    }

    func pairedAudioDevices() -> [BluetoothAudioDevice] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.filter(Self.isAudioOutput).map(Self.makeDevice)
    }

    // MARK: Discovery

    func startScan() {
        stopScan()
        discovered = []
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else { return }
        inquiry.inquiryLength = 12
        inquiry.updateNewDeviceNames = true
        if inquiry.start() == kIOReturnSuccess {
            self.inquiry = inquiry
            isScanning = true
        }
    }

    func stopScan() {
        inquiry?.stop()
        inquiry = nil
        isScanning = false
    }

    private func found(_ device: IOBluetoothDevice) {
        guard !device.isPaired(), Self.isAudioOutput(device) else { return }
        let item = Self.makeDevice(device)
        if let index = discovered.firstIndex(where: { $0.address == item.address }) {
            discovered[index] = item
        } else {
            discovered.append(item)
        }
    }

    // MARK: Pairing & connecting

    func pair(address: String, completion: @escaping (Bool) -> Void) {
        guard let device = device(address), let pairing = IOBluetoothDevicePair(device: device) else {
            return completion(false)
        }
        // Inquiry and paging share the radio; pairing is far more reliable without a scan running.
        stopScan()
        pairing.delegate = self
        pairings.append(pairing)
        pairCompletions[address] = completion
        if pairing.start() != kIOReturnSuccess {
            finishPairing(pairing, success: false)
        }
    }

    func connect(address: String, completion: @escaping (Bool) -> Void) {
        guard let device = device(address) else { return completion(false) }
        if device.isConnected() { return completion(true) }
        connectCompletions[address] = completion
        if device.openConnection(self) != kIOReturnSuccess {
            connectCompletions.removeValue(forKey: address)?(false)
        }
    }

    /// Target-action callback for `openConnection(_:)`.
    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        let address = BluetoothAddress.normalize(device.addressString ?? "")
        connectCompletions.removeValue(forKey: address)?(status == kIOReturnSuccess)
    }

    private func finishPairing(_ pairing: IOBluetoothDevicePair, success: Bool) {
        pairings.removeAll { $0 === pairing }
        guard let device = pairing.device() else { return }
        let address = BluetoothAddress.normalize(device.addressString ?? "")
        if success {
            discovered.removeAll { $0.address == address }
        }
        pairCompletions.removeValue(forKey: address)?(success)
    }

    // MARK: Helpers

    private func device(_ address: String) -> IOBluetoothDevice? {
        let pairs = stride(from: 0, to: address.count, by: 2).map { offset in
            let start = address.index(address.startIndex, offsetBy: offset)
            return String(address[start..<address.index(start, offsetBy: 2)])
        }
        return IOBluetoothDevice(addressString: pairs.joined(separator: "-"))
    }

    private static func isAudioOutput(_ device: IOBluetoothDevice) -> Bool {
        Int(device.deviceClassMajor) == kBluetoothDeviceClassMajorAudio
            && Int(device.deviceClassMinor) != kBluetoothDeviceClassMinorAudioMicrophone
    }

    private static func makeDevice(_ device: IOBluetoothDevice) -> BluetoothAudioDevice {
        let address = device.addressString ?? ""
        return BluetoothAudioDevice(
            address: BluetoothAddress.normalize(address),
            name: device.name ?? address.uppercased(),
            minorClass: Int(device.deviceClassMinor)
        )
    }
}

extension BluetoothManager: @MainActor IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        found(device)
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        found(device)
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        guard sender === inquiry else { return }
        inquiry = nil
        isScanning = false
    }
}

extension BluetoothManager: @MainActor IOBluetoothDevicePairDelegate {
    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        // Headphones have no display, so this is "Just Works" pairing: accept.
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        // Legacy headsets almost universally use 0000.
        var pin = BluetoothPINCode()
        pin.data.0 = 0x30; pin.data.1 = 0x30; pin.data.2 = 0x30; pin.data.3 = 0x30
        (sender as? IOBluetoothDevicePair)?.replyPINCode(4, pinCode: &pin)
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        guard let pairing = sender as? IOBluetoothDevicePair else { return }
        finishPairing(pairing, success: error == kIOReturnSuccess)
    }
}
