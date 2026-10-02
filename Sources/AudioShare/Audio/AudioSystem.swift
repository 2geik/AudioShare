import CoreAudio
import Foundation

/// A playable output as Core Audio sees it.
struct AudioOutput: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    let modelUID: String?

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Bluetooth outputs use "AA-BB-CC-DD-EE-FF:output" as their UID.
    var bluetoothAddress: String? {
        guard isBluetooth else { return nil }
        return BluetoothAddress.normalize(String(uid.prefix { $0 != ":" }))
    }
}

/// Thin, synchronous wrapper around the Core Audio HAL property API.
enum AudioSystem {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    // MARK: Devices

    static func outputs() -> [AudioOutput] {
        deviceIDs().compactMap { id in
            guard hasOutputStreams(id), uint32(id, kAudioDevicePropertyIsHidden) != 1 else { return nil }
            let transport = uint32(id, kAudioDevicePropertyTransportType) ?? 0
            guard transport != kAudioDeviceTransportTypeAggregate,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioOutput(id: id, uid: uid, name: name, transport: transport,
                               modelUID: string(id, kAudioDevicePropertyModelUID))
        }
    }

    static func deviceIDs() -> [AudioDeviceID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        deviceIDs().first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    static func uid(of id: AudioDeviceID) -> String? {
        string(id, kAudioDevicePropertyDeviceUID)
    }

    static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    // MARK: Default output

    static var defaultOutput: AudioDeviceID? {
        guard let id = uint32(system, kAudioHardwarePropertyDefaultOutputDevice), id != kAudioObjectUnknown else { return nil }
        return id
    }

    @discardableResult
    static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value) == noErr
    }

    // MARK: Volume

    /// Some devices expose volume on the main element, others (AirPods) only per channel.
    private static func volumeElements(_ id: AudioDeviceID) -> [AudioObjectPropertyElement] {
        if isVolumeSettable(id, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { isVolumeSettable(id, element: $0) }
    }

    private static func isVolumeSettable(_ id: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: element)
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    static func volume(_ id: AudioDeviceID) -> Float? {
        let values = volumeElements(id).compactMap { element -> Float? in
            var address = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    static func setVolume(_ id: AudioDeviceID, _ volume: Float) {
        var value = Float32(min(max(volume, 0), 1))
        for element in volumeElements(id) {
            var address = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: element)
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    // MARK: Sample rate

    static func availableSampleRates(_ id: AudioDeviceID) -> [AudioValueRange] {
        var address = Self.address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ranges) == noErr else { return [] }
        return ranges
    }

    @discardableResult
    static func setNominalSampleRate(_ id: AudioDeviceID, _ rate: Float64) -> Bool {
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        var value = rate
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value) == noErr
    }

    // MARK: Listening

    /// Calls `handler` on the main queue whenever the device list or the default output changes.
    static func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(system, &address, .main) { _, _ in
                MainActor.assumeIsolated { handler() }
            }
        }
    }

    // MARK: Primitives

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
