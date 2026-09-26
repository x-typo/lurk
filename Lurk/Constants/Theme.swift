import SwiftUI

enum Theme {
    static let background = Color(red: 0, green: 0, blue: 0)
    static let surface = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let surfaceElevated = Color(red: 0.167, green: 0.167, blue: 0.167)
    static let text = Color.white
    static let textSecondary = Color(red: 0.533, green: 0.533, blue: 0.533)
    static let textMuted = Color(red: 0.4, green: 0.4, blue: 0.4)
    static let primary = Color(red: 1, green: 0.271, blue: 0) // Reddit orange #ff4500
    static let swipeOpen = Color(red: 0, green: 0.478, blue: 1) // #007AFF
    static let swipeHide = Color(red: 0.8, green: 0.2, blue: 0.2) // #CC3333
    static let downvote = Color(red: 0.384, green: 0.498, blue: 1) // Reddit periwinkle #6180FF
    static let opBadge = Color(red: 0, green: 0.478, blue: 1) // #007AFF
    static let border = Color(red: 0.2, green: 0.2, blue: 0.2)
    static let swipeReply = Color(red: 0.114, green: 0.620, blue: 0.459) // #1D9E75
    // A faint orange behind the comment a thread was opened for.
    static let focusedComment = Color(red: 0.165, green: 0.102, blue: 0.071) // #2A1A12
    // One rail color per reply level, repeating past the last entry.
    static let commentRails = [
        primary,
        Color(red: 0.216, green: 0.541, blue: 0.867), // #378ADD
        swipeReply,
        Color(red: 0.498, green: 0.467, blue: 0.867), // #7F77DD
        Color(red: 0.937, green: 0.624, blue: 0.153), // #EF9F27
    ]
}
