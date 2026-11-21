import CoreGraphics
import Foundation

/// The named sizes offered by both raster brushes.
nonisolated enum MarkupBrushSize: CaseIterable, Hashable {
    case small
    case medium
    case large
    case extraLarge

    var title: LocalizedStringResource {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var diameter: CGFloat {
        switch self {
        case .small: 16
        case .medium: 32
        case .large: 64
        case .extraLarge: 96
        }
    }
}
