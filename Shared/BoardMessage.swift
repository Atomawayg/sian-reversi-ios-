import Foundation

/// Which game the screen shows.
enum GameKind: Int, Codable {
    case reversi = 0      // WePlay Reversi (8x8, holes allowed)
    case checkers = 1     // WePlay หมากฮอส (8x8, you at the bottom)
    case connect4 = 2     // Plato 4 in a Row (7x6)
    case connect5 = 3     // Plato 5 in a Row (9x7)

    var size: (w: Int, h: Int) {
        switch self { case .reversi, .checkers: return (8, 8); case .connect4: return (7, 6); case .connect5: return (9, 7) }
    }
}

/// What the screen reader (broadcast extension) sends to the app.
struct BoardMessage: Codable, Equatable {
    /// false when no supported board is visible on screen
    var valid: Bool
    var game: GameKind = .reversi
    /// w*h values, row-major from the top-left.
    /// reversi: 0 empty, 1 black, 2 white, 3 hole · checkers: 0 empty, 1 red, 2 purple · connect: 0 empty, 1 red, 2 yellow
    var cells: [Int]
    /// your colour (same codes as cells), 0 unknown
    var me: Int
    /// true when the game shows it is your move
    var myTurn: Bool
}

enum Link {
    static let port: UInt16 = 52741
}
