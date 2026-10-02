import AppKit

enum SystemSettings {
    static func openSound() {
        open("x-apple.systempreferences:com.apple.Sound-Settings.extension")
    }

    static func openBluetooth() {
        open("x-apple.systempreferences:com.apple.BluetoothSettings")
    }

    static func openBluetoothPrivacy() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
