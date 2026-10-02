import AppKit
import CoreAudio
import IOBluetooth

/// One row in the menu: a Core Audio output, a paired-but-disconnected Bluetooth device,
/// or a nearby Bluetooth device that has never been paired.
struct OutputDevice: Identifiable, Equatable {
    enum State: Equatable {
        case available
        case disconnected
        case unpaired
        case connecting
        case pairing
        case failed
    }

    /// Stable across connects/disconnects: "bt:<ADDRESS>" for Bluetooth, the Core Audio UID otherwise.
    let id: String
    let name: String
    let kind: DeviceKind
    var state: State
    var output: AudioOutput?
    var bluetoothAddress: String?

    var isAvailable: Bool { output != nil }
    var isBusy: Bool { state == .connecting || state == .pairing }

    static func key(for output: AudioOutput) -> String {
        output.bluetoothAddress.map(key(bluetoothAddress:)) ?? output.uid
    }

    static func key(bluetoothAddress: String) -> String {
        "bt:\(bluetoothAddress)"
    }
}

enum DeviceKind: Equatable {
    case airPods, airPodsGen3, airPodsPro, airPodsMax
    case beatsHeadphones, beatsEarbuds
    case headphones, speaker, car
    case laptop, desktop, display, airPlay, virtual, generic

    /// The first candidate this macOS version knows, so newer symbols degrade gracefully.
    var symbolName: String {
        let candidates: [String] = switch self {
        case .airPods: ["airpods", "headphones"]
        case .airPodsGen3: ["airpods.gen3", "airpods", "headphones"]
        case .airPodsPro: ["airpods.pro", "airpodspro", "headphones"]
        case .airPodsMax: ["airpods.max", "airpodsmax", "headphones"]
        case .beatsHeadphones: ["beats.headphones", "headphones"]
        case .beatsEarbuds: ["beats.earphones", "earbuds", "headphones"]
        case .headphones: ["headphones"]
        case .speaker: ["hifispeaker.fill", "hifispeaker"]
        case .car: ["car.fill"]
        case .laptop: ["laptopcomputer"]
        case .desktop: ["desktopcomputer"]
        case .display: ["display"]
        case .airPlay: ["airplay.audio", "airplayaudio"]
        case .virtual: ["waveform"]
        case .generic: ["speaker.wave.2.fill"]
        }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "speaker.wave.2.fill"
    }

    init(output: AudioOutput) {
        switch output.transport {
        case kAudioDeviceTransportTypeBuiltIn: self = output.name.contains("MacBook") ? .laptop : .desktop
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: self = .display
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            self = Self(appleModelUID: output.modelUID) ?? Self(name: output.name) ?? .headphones
        default: self = .generic
        }
    }

    init(bluetooth device: BluetoothAudioDevice, modelUID: String?) {
        self = Self(appleModelUID: modelUID)
            ?? Self(name: device.name)
            ?? Self(minorClass: device.minorClass)
    }

    /// Core Audio reports Apple/Beats Bluetooth models as "<product id> <vendor id>", e.g. "2014 4c".
    private init?(appleModelUID: String?) {
        let parts = appleModelUID?.lowercased().split(separator: " ") ?? []
        guard parts.count == 2, parts[1] == "4c", let product = Int(parts[0], radix: 16) else { return nil }
        switch product {
        case 0x2002, 0x200F: self = .airPods
        case 0x2013, 0x2019, 0x201B: self = .airPodsGen3
        case 0x200E, 0x2014, 0x2024, 0x2027: self = .airPodsPro
        case 0x200A, 0x201F: self = .airPodsMax
        case 0x2006, 0x2009, 0x200C, 0x2017, 0x2025: self = .beatsHeadphones
        case 0x2003, 0x2005, 0x200B, 0x200D, 0x2010, 0x2011, 0x2012, 0x2016, 0x201D, 0x2026: self = .beatsEarbuds
        default: return nil
        }
    }

    private init?(name: String) {
        let name = name.lowercased()
        if name.contains("airpods pro") { self = .airPodsPro }
        else if name.contains("airpods max") { self = .airPodsMax }
        else if name.contains("airpods") { self = .airPods }
        else if name.contains("beats") { self = .beatsHeadphones }
        else { return nil }
    }

    private init(minorClass: Int) {
        switch minorClass {
        case kBluetoothDeviceClassMinorAudioLoudspeaker,
             kBluetoothDeviceClassMinorAudioPortable,
             kBluetoothDeviceClassMinorAudioHiFi:
            self = .speaker
        case kBluetoothDeviceClassMinorAudioCar:
            self = .car
        default:
            self = .headphones
        }
    }
}
