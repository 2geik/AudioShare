import SwiftUI

/// Metrics shared by every row so text lines up the way it does in the system's
/// Bluetooth and Sound menus.
enum MenuMetrics {
    static let width: CGFloat = 300
    static let outerPadding: CGFloat = 5
    static let rowPadding: CGFloat = 9
    static let iconSize: CGFloat = 26
    static let iconSpacing: CGFloat = 8

    /// Liquid Glass panels are much rounder; keep the hover highlight concentric with them.
    static var highlightRadius: CGFloat {
        if #available(macOS 26, *) { 10 } else { 5 }
    }
}

/// Padding plus the soft gray hover highlight used by Control Center–style menus.
struct MenuRowModifier: ViewModifier {
    var verticalPadding: CGFloat = 4
    // Spelled out instead of `@State`: the macOS 27 SDK turns `@State` into a macro whose
    // plugin ships only with Xcode, and this project builds with the Command Line Tools.
    private let isHovered = State(initialValue: false)
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, MenuMetrics.rowPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background {
                if isHovered.wrappedValue && isEnabled {
                    RoundedRectangle(cornerRadius: MenuMetrics.highlightRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                }
            }
            .onHover { isHovered.wrappedValue = $0 }
    }
}

extension View {
    func menuRow(verticalPadding: CGFloat = 4) -> some View {
        modifier(MenuRowModifier(verticalPadding: verticalPadding))
    }
}

struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, MenuMetrics.rowPadding)
            .padding(.vertical, 5)
    }
}

struct MenuSectionHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            accessory
        }
        .frame(height: 18)
        .padding(.horizontal, MenuMetrics.rowPadding)
        .padding(.bottom, 2)
    }
}

extension MenuSectionHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

/// A plain text menu item, e.g. "Sound Settings…".
struct MenuItemButton: View {
    let title: LocalizedStringKey
    var isChecked = false
    var shortcut: String?
    let action: () -> Void

    init(_ title: LocalizedStringKey, isChecked: Bool = false, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isChecked = isChecked
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .font(.system(size: 13))
            .menuRow(verticalPadding: 3)
        }
        .buttonStyle(.plain)
    }
}

/// The round icon from Control Center: accent-filled when on, gray when off.
struct DeviceIcon: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: MenuMetrics.iconSize, height: MenuMetrics.iconSize)
            .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.1)))
    }
}
