import SwiftUI
import Systems42Kit

/// How an area looks in the sidebar. The area names are the only fixed names (CON-006).
extension Area {
    var label: String {
        switch self {
        case .requirements: "Requirements"
        case .architecture: "Architecture"
        case .commons: "Commons"
        }
    }

    var color: Color {
        switch self {
        case .requirements: .blue
        case .architecture: .orange
        case .commons: .green
        }
    }
}
