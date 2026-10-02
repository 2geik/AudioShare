import AppKit
import CoreAudio
import Observation

/// Owns the device list, the user's selection and the shared multi-output device.
@Observable
final class AudioShareController {
    private(set) var outputs: [AudioOutput] = []
    private(set) var paired: [BluetoothAudioDevice] = []
    private(set) var isSharing = false
    private(set) var volumes: [String: Float] = [:]
    private(set) var launchAtLogin = LaunchAtLogin.isEnabled
    private(set) var errorMessage: String?
    /// Transient per-device state (connecting, pairing, failed), keyed by `OutputDevice.id`.
    private(set) var activity: [String: OutputDevice.State] = [:]
    /// Device keys in the order they were picked. Remembered across launches, so a device that
    /// drops out and reconnects rejoins the share on its own.
    private(set) var selection: [String] {
        didSet { defaults.set(selection, forKey: Keys.selection) }
    }

    let bluetooth = BluetoothManager()

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var aggregateID: AudioDeviceID?
    @ObservationIgnored private var memberUIDs: [String] = []
    /// The output to return to when sharing ends. Persisted so a crash can be undone on next launch.
    @ObservationIgnored private var previousOutputUID: String? {
        didSet { defaults.set(previousOutputUID, forKey: Keys.previousOutput) }
    }
    @ObservationIgnored private var isSwitchingOutput = false
    @ObservationIgnored private var connectAttempts: [String: UUID] = [:]
    /// Bluetooth address → Core Audio model UID, so a disconnected device keeps its proper icon.
    @ObservationIgnored private var modelUIDs: [String: String] {
        didSet { defaults.set(modelUIDs, forKey: Keys.modelUIDs) }
    }

    private enum Keys {
        static let selection = "selection"
        static let modelUIDs = "modelUIDs"
        static let previousOutput = "previousOutput"
    }

    init() {
        selection = defaults.stringArray(forKey: Keys.selection) ?? []
        modelUIDs = defaults.dictionary(forKey: Keys.modelUIDs) as? [String: String] ?? [:]
        previousOutputUID = defaults.string(forKey: Keys.previousOutput)
    }

    func start() {
        // After a crash our device can still exist and even be the system output: put things back.
        if let current = AudioSystem.defaultOutput, MultiOutputDevice.isOurs(current),
           let previous = previousOutputUID.flatMap(AudioSystem.deviceID(forUID:)) {
            AudioSystem.setDefaultOutput(previous)
        }
        MultiOutputDevice.destroyExisting()
        AudioSystem.observeChanges { [weak self] in self?.refresh() }
        refresh()
    }

    // MARK: Derived state

    var devices: [OutputDevice] {
        var result = outputs.map { output in
            let key = OutputDevice.key(for: output)
            return OutputDevice(id: key, name: output.name, kind: DeviceKind(output: output),
                                state: activity[key] ?? .available, output: output,
                                bluetoothAddress: output.bluetoothAddress)
        }
        let connected = Set(result.compactMap(\.bluetoothAddress))
        for device in paired where !connected.contains(device.address) {
            let key = OutputDevice.key(bluetoothAddress: device.address)
            result.append(OutputDevice(id: key, name: device.name,
                                       kind: DeviceKind(bluetooth: device, modelUID: modelUIDs[device.address]),
                                       state: activity[key] ?? .disconnected, output: nil,
                                       bluetoothAddress: device.address))
        }
        return result
    }

    var nearbyDevices: [OutputDevice] {
        let known = Set(paired.map(\.address))
        return bluetooth.discovered.filter { !known.contains($0.address) }.map { device in
            let key = OutputDevice.key(bluetoothAddress: device.address)
            return OutputDevice(id: key, name: device.name, kind: DeviceKind(bluetooth: device, modelUID: nil),
                                state: activity[key] ?? .unpaired, output: nil, bluetoothAddress: device.address)
        }
    }

    /// Selected devices that can play right now, in selection order.
    var selectedOutputs: [AudioOutput] {
        selection.compactMap { key in outputs.first { OutputDevice.key(for: $0) == key } }
    }

    var canShare: Bool { selectedOutputs.count >= 2 }

    func isSelected(_ device: OutputDevice) -> Bool {
        device.isAvailable && selection.contains(device.id)
    }

    // MARK: Actions

    func toggle(_ device: OutputDevice) {
        guard !device.isBusy else { return }
        if device.isAvailable {
            if isSelected(device) {
                selection.removeAll { $0 == device.id }
            } else {
                select(device.id)
            }
            syncSharing()
        } else if let address = device.bluetoothAddress {
            if paired.contains(where: { $0.address == address }) {
                connect(device.id, address: address)
            } else {
                pair(device.id, address: address)
            }
        }
    }

    func setSharing(_ enabled: Bool) {
        enabled ? startSharing() : stopSharing()
    }

    func setVolume(_ volume: Float, for device: OutputDevice) {
        guard let output = device.output else { return }
        AudioSystem.setVolume(output.id, volume)
        volumes[device.id] = volume
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.set(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func refresh() {
        outputs = AudioSystem.outputs()
        if !BluetoothManager.isPermissionDenied {
            paired = bluetooth.pairedAudioDevices()
        }
        launchAtLogin = LaunchAtLogin.isEnabled

        var volumes: [String: Float] = [:]
        for output in outputs {
            let key = OutputDevice.key(for: output)
            volumes[key] = AudioSystem.volume(output.id)
            if activity[key] == .connecting || activity[key] == .failed {
                activity[key] = nil
            }
            if let address = output.bluetoothAddress, let model = output.modelUID, modelUIDs[address] != model {
                modelUIDs[address] = model
            }
        }
        self.volumes = volumes

        // Someone picked another output in the Sound menu or System Settings: step aside.
        if isSharing, !isSwitchingOutput, let aggregateID, AudioSystem.defaultOutput != aggregateID {
            stopSharing(restoreOutput: false)
        }
        syncSharing()
    }

    // MARK: Sharing

    private func startSharing() {
        guard !isSharing, canShare else { return }
        if let current = AudioSystem.defaultOutput, !MultiOutputDevice.isOurs(current) {
            previousOutputUID = AudioSystem.uid(of: current)
        }
        errorMessage = nil
        isSharing = true
        syncSharing()
    }

    func stopSharing(restoreOutput: Bool = true) {
        guard isSharing else { return MultiOutputDevice.destroyExisting() }
        let remaining = selectedOutputs
        isSharing = false
        aggregateID = nil
        memberUIDs = []
        isSwitchingOutput = false
        if restoreOutput {
            // Hand the output back before removing ours, so macOS doesn't pick one at random.
            let previous = previousOutputUID.flatMap(AudioSystem.deviceID(forUID:))
            if let target = previous ?? remaining.first?.id {
                AudioSystem.setDefaultOutput(target)
            }
        }
        MultiOutputDevice.destroyExisting()
    }

    /// Keeps the multi-output device in step with the selection and with what's actually connected.
    private func syncSharing() {
        guard isSharing else { return }
        let members = selectedOutputs
        guard members.count >= 2 else {
            // Down to one device: just play there, like iOS does when the other AirPods leave.
            if let last = members.first {
                previousOutputUID = last.uid
            }
            return stopSharing()
        }
        guard members.map(\.uid) != memberUIDs else { return }

        do {
            let id = try MultiOutputDevice.create(members: members)
            aggregateID = id
            memberUIDs = members.map(\.uid)
            makeDefaultOutput(id)
        } catch {
            errorMessage = String(localized: "Couldn't create the shared output.")
            stopSharing()
        }
    }

    /// A freshly created aggregate can take a moment before the HAL accepts it as the default.
    private func makeDefaultOutput(_ id: AudioDeviceID) {
        isSwitchingOutput = true
        Task {
            for _ in 0..<20 {
                if AudioSystem.setDefaultOutput(id), AudioSystem.defaultOutput == id { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if aggregateID == id {
                isSwitchingOutput = false
            }
        }
    }

    // MARK: Bluetooth

    private func select(_ key: String) {
        if !selection.contains(key) {
            selection.append(key)
        }
    }

    private func connect(_ key: String, address: String) {
        activity[key] = .connecting
        select(key)
        bluetooth.connect(address: address) { [weak self] success in
            if !success { self?.fail(key) }
        }
        // Core Audio publishes the output a few seconds after the link is up; refresh() clears the state.
        let attempt = UUID()
        connectAttempts[key] = attempt
        Task {
            try? await Task.sleep(for: .seconds(20))
            if connectAttempts[key] == attempt, activity[key] == .connecting { fail(key) }
        }
    }

    private func pair(_ key: String, address: String) {
        activity[key] = .pairing
        bluetooth.pair(address: address) { [weak self] success in
            guard let self else { return }
            guard success else { return fail(key) }
            paired = bluetooth.pairedAudioDevices()
            connect(key, address: address)
        }
    }

    private func fail(_ key: String) {
        activity[key] = .failed
        selection.removeAll { $0 == key }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if activity[key] == .failed { activity[key] = nil }
        }
    }
}
