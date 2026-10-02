import SwiftUI

struct DeviceRow: View {
    let device: OutputDevice
    let isSelected: Bool
    var volume: Float?
    let onToggle: () -> Void
    var onVolumeChange: (Float) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: MenuMetrics.iconSpacing) {
                    DeviceIcon(symbol: device.kind.symbolName, isOn: isSelected)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(device.state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        }
                    }
                    Spacer(minLength: 4)
                    if device.isBusy {
                        ProgressView().controlSize(.small)
                    }
                }
                .menuRow(verticalPadding: 3)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected, let volume {
                VolumeSlider(value: volume, onChange: onVolumeChange)
                    .padding(.leading, MenuMetrics.rowPadding + MenuMetrics.iconSize + MenuMetrics.iconSpacing)
                    .padding(.trailing, MenuMetrics.rowPadding)
                    .padding(.bottom, 4)
            }
        }
    }

    private var subtitle: LocalizedStringKey? {
        switch device.state {
        case .available: nil
        case .disconnected: "Not Connected"
        case .unpaired: "Click to Pair"
        case .connecting: "Connecting…"
        case .pairing: "Pairing…"
        case .failed: "Couldn't Connect"
        }
    }
}

private struct VolumeSlider: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
            Slider(value: Binding(get: { Double(value) }, set: { onChange(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .accessibilityLabel(Text("Volume"))
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
}
