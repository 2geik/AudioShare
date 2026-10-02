import CoreAudio
import Foundation

/// Creates and tears down the public multi-output (stacked aggregate) device that mirrors
/// the system output to every selected device — what Audio MIDI Setup calls a "Multi-Output Device".
enum MultiOutputDevice {
    static let uid = "io.github.2geik.AudioShare.multioutput"
    static let name = "AudioShare"

    struct CreationError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "AudioHardwareCreateAggregateDevice failed (\(status))" }
    }

    /// - Parameter members: the outputs to mirror, in the order the user picked them.
    static func create(members: [AudioOutput]) throws -> AudioDeviceID {
        destroyExisting()

        // The clock source should be the steadiest device: anything wired beats Bluetooth.
        let main = members.first { !$0.isBluetooth } ?? members[0]
        let subdevices: [[String: Any]] = members.map { member in
            [
                kAudioSubDeviceUIDKey: member.uid,
                kAudioSubDeviceDriftCompensationKey: member.uid == main.uid ? 0 : 1,
            ]
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: main.uid,
            kAudioAggregateDeviceSubDeviceListKey: subdevices,
        ]

        var id = AudioDeviceID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr, id != kAudioObjectUnknown else { throw CreationError(status: status) }

        if let rate = commonSampleRate(members) {
            AudioSystem.setNominalSampleRate(id, rate)
        }
        return id
    }

    /// Removes our device, including one left behind by a crash.
    static func destroyExisting() {
        for id in AudioSystem.deviceIDs() where AudioSystem.uid(of: id) == uid {
            AudioHardwareDestroyAggregateDevice(id)
        }
    }

    static func isOurs(_ id: AudioDeviceID) -> Bool {
        AudioSystem.uid(of: id) == uid
    }

    /// Bluetooth headphones are usually locked to 48 kHz (or 44.1), so pick a rate every member supports.
    private static func commonSampleRate(_ members: [AudioOutput]) -> Float64? {
        let supported = members.map { AudioSystem.availableSampleRates($0.id) }
        return [48_000, 44_100, 96_000, 88_200].first { rate in
            supported.allSatisfy { ranges in ranges.contains { $0.mMinimum <= rate && rate <= $0.mMaximum } }
        }
    }
}
