import SwiftUI

enum GroundedTheme {
    static let calmGreen = Color(red: 0.35, green: 0.55, blue: 0.42)
    /// Readable tan-brown for body copy.
    static let warmEarth = Color(red: 0.56, green: 0.46, blue: 0.36)
    /// Light gray for soft subtitles and accents.
    static let softMist = Color(red: 0.64, green: 0.64, blue: 0.62)
    static let softSage = Color(red: 0.72, green: 0.78, blue: 0.70)

    /// Softer than system red for the blocking state.
    static let gentleRust = Color(red: 0.72, green: 0.48, blue: 0.42)

    static var screenBackground: Color { softSage.opacity(0.15) }
    static var cardBackground: Color { softSage.opacity(0.35) }
    static var accentBackground: Color { calmGreen.opacity(0.10) }
}

extension View {
    func groundedScreen() -> some View {
        background(GroundedTheme.screenBackground)
            .tint(GroundedTheme.calmGreen)
    }

    func groundedListScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(GroundedTheme.screenBackground)
            .tint(GroundedTheme.calmGreen)
    }
}
