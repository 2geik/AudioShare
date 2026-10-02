import AppKit

/// Watches the keyboard's volume keys with a passive event monitor. It needs no permission; it only
/// observes, so macOS still gets the key too. If macOS ever withholds these events without a
/// permission, the monitor simply stays quiet.
final class VolumeKeyMonitor {
    enum Key { case up, down, mute }

    private var monitors: [Any] = []

    // NX_KEYTYPE_* from <IOKit/hidsystem/ev_keymap.h>, carried by "system defined" events of subtype 8.
    private static let auxControlButtons: Int16 = 8
    private static let keys: [Int: Key] = [0: .up, 1: .down, 7: .mute]

    func start(_ handler: @escaping (Key, _ isFine: Bool) -> Void) {
        let handle: (NSEvent) -> Void = { event in
            guard event.subtype.rawValue == Self.auxControlButtons,
                  let key = Self.keys[(event.data1 & 0xFFFF_0000) >> 16],
                  (event.data1 & 0xFF00) >> 8 == 0xA // key down (repeats included)
            else { return }
            // ⌥⇧ gives quarter steps, as it does for the system volume.
            handler(key, event.modifierFlags.contains([.option, .shift]))
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: handle) {
            monitors.append(global)
        }
        // Global monitors skip events sent to our own app, e.g. while the menu panel is focused.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { handle($0); return $0 }) {
            monitors.append(local)
        }
    }
}
