import AppKit
import CoreAudio
import Observation

/// Owns the device list, the user's selection and the shared multi-output device.
@Observable
final class AudioShareController {
    private(set) var outputs: [AudioOutput] = []
    private(set) var paired: [BluetoothAudioDevice] = []
    /// The user wants sharing on. While waiting for a device that dropped out, audio plays on the rest.
    private(set) var isSharing = false
    /// Device keys that were sharing and dropped out; they rejoin automatically when they're back.
    private(set) var waitingFor: [String] = []
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
    /// The device we made the system output: the multi-output device, or the last one left while waiting.
    @ObservationIgnored private var routedOutputID: AudioDeviceID?
    /// Core Audio UIDs currently playing.
    @ObservationIgnored private var memberUIDs: [String] = []
    /// Every device that has played during this share, so a dropout can be told apart from a deselection.
    @ObservationIgnored private var sessionKeys: Set<String> = []
    @ObservationIgnored private let volumeKeys = VolumeKeyMonitor()
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
        volumeKeys.start { [weak self] key, isFine in self?.handleVolumeKey(key, isFine: isFine) }
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
                sessionKeys.remove(device.id)
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
        // A member coming or going can move the system output too, so leave that to syncSharing().
        let membershipChanged = Set(selectedOutputs.map(\.uid)) != Set(memberUIDs)
        if isSharing, !isSwitchingOutput, !membershipChanged,
           let routedOutputID, AudioSystem.defaultOutput != routedOutputID {
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
        waitingFor = []
        sessionKeys = []
        memberUIDs = []
        aggregateID = nil
        routedOutputID = nil
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

    /// Keeps the system output in step with the selection and with what's actually connected.
    private func syncSharing() {
        guard isSharing else { return }
        let members = selectedOutputs
        let memberKeys = Set(members.map(OutputDevice.key(for:)))
        let dropped = selection.filter { sessionKeys.contains($0) && !memberKeys.contains($0) }

        if members.count >= 2 {
            waitingFor = []
            playOnAll(members)
        } else if let last = members.first, !dropped.isEmpty {
            // Like iOS when the other AirPods go back in their case, except the share resumes
            // by itself once they reconnect.
            waitingFor = dropped
            playOnly(last)
        } else {
            // Down to one device by choice: just play there.
            if let last = members.first {
                previousOutputUID = last.uid
            }
            stopSharing()
        }
    }

    private func playOnAll(_ members: [AudioOutput]) {
        guard aggregateID == nil || members.map(\.uid) != memberUIDs else { return }
        do {
            let id = try MultiOutputDevice.create(members: members)
            aggregateID = id
            memberUIDs = members.map(\.uid)
            sessionKeys.formUnion(members.map(OutputDevice.key(for:)))
            route(to: id)
        } catch {
            errorMessage = String(localized: "Couldn't create the shared output.")
            stopSharing()
        }
    }

    private func playOnly(_ output: AudioOutput) {
        guard routedOutputID != output.id else { return }
        memberUIDs = [output.uid]
        route(to: output.id)
        if aggregateID != nil {
            aggregateID = nil
            MultiOutputDevice.destroyExisting()
        }
    }

    /// A freshly created multi-output device can take a moment before the HAL accepts it as the default.
    private func route(to id: AudioDeviceID) {
        routedOutputID = id
        if AudioSystem.setDefaultOutput(id), AudioSystem.defaultOutput == id { return }
        isSwitchingOutput = true
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(50))
                if AudioSystem.setDefaultOutput(id), AudioSystem.defaultOutput == id { break }
            }
            if routedOutputID == id {
                isSwitchingOutput = false
            }
        }
    }

    // MARK: Volume keys

    /// macOS can't change the volume of a multi-output device, so apply the keys to every member,
    /// keeping their balance. When only one device is left, macOS handles the keys itself.
    private func handleVolumeKey(_ key: VolumeKeyMonitor.Key, isFine: Bool) {
        guard let aggregateID, routedOutputID == aggregateID, AudioSystem.defaultOutput == aggregateID else { return }
        let members = selectedOutputs.filter { memberUIDs.contains($0.uid) }
        let step: Float = isFine ? 1 / 64 : 1 / 16
        switch key {
        case .up, .down:
            for member in members {
                let current = AudioSystem.volume(member.id) ?? 0
                AudioSystem.setVolume(member.id, current + (key == .up ? step : -step))
                if key == .up {
                    AudioSystem.setMuted(member.id, false)
                }
            }
        case .mute:
            let mute = !members.allSatisfy { AudioSystem.isMuted($0.id) }
            members.forEach { AudioSystem.setMuted($0.id, mute) }
        }
        for member in members {
            volumes[OutputDevice.key(for: member)] = AudioSystem.volume(member.id)
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
