import AppKit
import SwiftUI

/// Uses AppKit's minimal color well because SwiftUI ColorPicker cannot select this compact native style.
struct MarkupColorWell: NSViewRepresentable {
    @Binding var color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .minimal)
        well.supportsAlpha = false
        well.controlSize = .regular
        well.target = context.coordinator
        well.action = #selector(Coordinator.changeColor(_:))
        well.toolTip = String(localized: "Color")
        well.setAccessibilityLabel(String(localized: "Color"))
        well.sizeToFit()
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.color = $color
        let selectedColor = NSColor(color)
        if well.color != selectedColor { well.color = selectedColor }
        well.isEnabled = isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSColorWell, context: Context) -> CGSize? {
        nsView.fittingSize
    }

    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        well.deactivate()
    }

    /// Connects the native color well's action to the editor's SwiftUI color binding.
    final class Coordinator: NSObject {
        var color: Binding<Color>

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func changeColor(_ sender: NSColorWell) {
            color.wrappedValue = Color(nsColor: sender.color)
        }
    }
}
