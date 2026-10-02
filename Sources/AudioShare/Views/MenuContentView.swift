import SwiftUI

struct MenuContentView: View {
    let controller: AudioShareController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MenuDivider()

            if BluetoothManager.isPermissionDenied {
                permissionRow
                MenuDivider()
            }

            MenuSectionHeader("Devices")
            ForEach(controller.devices) { device in
                DeviceRow(
                    device: device,
                    isSelected: controller.isSelected(device),
                    volume: controller.volumes[device.id],
                    onToggle: { controller.toggle(device) },
                    onVolumeChange: { controller.setVolume($0, for: device) }
                )
            }
            MenuDivider()

            nearbySection
            MenuDivider()

            MenuItemButton("Open at Login", isChecked: controller.launchAtLogin) {
                controller.setLaunchAtLogin(!controller.launchAtLogin)
            }
            MenuItemButton("Sound Settings…", action: SystemSettings.openSound)
            MenuItemButton("Bluetooth Settings…", action: SystemSettings.openBluetooth)
            MenuDivider()
            MenuItemButton("Quit AudioShare", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(MenuMetrics.outerPadding)
        .frame(width: MenuMetrics.width)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            controller.refresh()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Audio Sharing")
                    .font(.system(size: 13, weight: .semibold))
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Toggle("Audio Sharing", isOn: Binding(get: { controller.isSharing }, set: controller.setSharing))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!controller.isSharing && !controller.canShare)
        }
        .padding(.horizontal, MenuMetrics.rowPadding)
        .padding(.vertical, 4)
    }

    private var status: LocalizedStringKey {
        let count = controller.selectedOutputs.count
        if let error = controller.errorMessage {
            return "\(error)"
        } else if controller.isSharing, !controller.waitingFor.isEmpty {
            let names = controller.waitingFor.compactMap { key in
                controller.devices.first { $0.id == key }?.name
            }
            // Join names in the language the menu is shown in ("A and B", "A ve B"), not the region's.
            let language = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
            let list = names.formatted(.list(type: .and).locale(language))
            return names.isEmpty ? "Waiting for a device" : "Waiting for \(list)"
        } else if controller.isSharing {
            return "Playing on \(count) devices"
        } else if count >= 2 {
            return "Ready to share with \(count) devices"
        } else {
            return "Choose at least two devices"
        }
    }

    private var permissionRow: some View {
        Button(action: SystemSettings.openBluetoothPrivacy) {
            HStack(spacing: MenuMetrics.iconSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .frame(width: MenuMetrics.iconSize, height: MenuMetrics.iconSize)
                    .background(Circle().fill(.orange))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bluetooth Access Needed")
                        .font(.system(size: 13))
                    Text("Allow AudioShare in Privacy & Security.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .menuRow(verticalPadding: 3)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var nearbySection: some View {
        let nearby = controller.nearbyDevices
        let isScanning = controller.bluetooth.isScanning

        MenuSectionHeader(title: "Nearby Devices") {
            if isScanning {
                ProgressView().controlSize(.mini)
            }
        }
        ForEach(nearby) { device in
            DeviceRow(device: device, isSelected: false, onToggle: { controller.toggle(device) })
        }
        if isScanning {
            if nearby.isEmpty {
                Text("Put headphones in pairing mode. For AirPods, hold the button on the case.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MenuMetrics.rowPadding)
                    .padding(.vertical, 3)
            }
        } else {
            MenuItemButton(nearby.isEmpty ? "Search for Devices" : "Search Again") {
                controller.bluetooth.startScan()
            }
            .disabled(BluetoothManager.isPermissionDenied)
        }
    }
}
