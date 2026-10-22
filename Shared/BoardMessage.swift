import Foundation

/// Which game the screen shows.
enum GameKind: Int, Codable {
    case reversi = 0      // WePlay Reversi (8x8, holes allowed)
    case checkers = 1     // WePlay หมากฮอส (8x8, you at the bottom)
    case connect4 = 2     // Plato 4 in a Row (7x6)
    case connect5 = 3     // Plato 5 in a Row (9x7)
    case jackaroo = 4     // WePlay Jackaroo (see JK layout)

    var size: (w: Int, h: Int) {
        switch self { case .reversi, .checkers: return (8, 8); case .connect4: return (7, 6); case .connect5: return (9, 7); case .jackaroo: return (JK.count, 1) }
    }
}

/// What the screen reader (broadcast extension) sends to the app.
struct BoardMessage: Codable, Equatable {
    /// false when no supported board is visible on screen
    var valid: Bool
    var game: GameKind = .reversi
    /// w*h values, row-major from the top-left.
    /// reversi: 0 empty, 1 black, 2 white, 3 hole · checkers: 0 empty, 1 red, 2 purple, 3 red king, 4 purple king · connect: 0 empty, 1 red, 2 yellow
    var cells: [Int]
    /// your colour (same codes as cells), 0 unknown
    var me: Int
    /// true when the game shows it is your move
    var myTurn: Bool
}

enum Link {
    static let port: UInt16 = 52741
}

/// Jackaroo message layout (cells): colours 0 none, 1 green, 2 red, 3 blue, 4 orange.
enum JK {
    static let track = 0        // 76 track holes
    static let lanes = 76       // + 4*seat + slot
    static let homes = 92       // + 4*seat + slot
    static let seats = 108      // colour of each seat 0..3
    static let hand = 112       // up to 5 cards: 1 A, 2…10, 11 J, 12 Q, 13 K
    static let count = 117
    static let rankNames = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
}
