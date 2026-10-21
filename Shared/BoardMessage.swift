import Foundation

/// What the screen reader (broadcast extension) sends to the app over UDP on localhost.
struct BoardMessage: Codable, Equatable {
    /// false when no Reversi board is visible on screen
    var valid: Bool
    /// 64 values, row-major from A1: 0 empty, 1 black, 2 white, 3 hole/cut
    var cells: [Int]
    /// your colour read from the score tile beside your avatar: 1 black, 2 white, 0 unknown
    var me: Int
    /// true when the game highlights your legal moves (yellow glow)
    var myTurn: Bool
}

enum Link {
    static let port: UInt16 = 52741
}
