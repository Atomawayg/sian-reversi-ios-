import Foundation

/// Which game the screen shows.
enum GameKind: Int, Codable {
    case reversi = 0      // WePlay Reversi (8x8, holes allowed)
    case checkers = 1     // WePlay หมากฮอส (8x8, you at the bottom)
    case connect4 = 2     // Plato 4 in a Row (7x6)
    case connect5 = 3     // Plato 5 in a Row (9x7)
    case jackaroo = 4     // WePlay Jackaroo (see JK layout)
    case chess = 5        // Plato chess: 64 cells from the top-left of the screen, 0 empty, 1…6 white P N B R Q K, 7…12 black; me 1 white / 2 black
    case draughts = 6     // Plato checkers (English rules): 64 cells, 0 empty, 1 red, 2 white, 3 red king, 4 white king
    case suika = 7        // WePlay Frog Watermelon (fruit merge): see SK layout
    case pool = 8         // WePlay Pool / 8-ball: see PoolCodec layout
    case tilePush = 9     // WePlay Tile Push (4×4): see TP layout

    var size: (w: Int, h: Int) {
        switch self { case .reversi, .checkers, .chess, .draughts: return (8, 8); case .connect4: return (7, 6); case .connect5: return (9, 7); case .jackaroo: return (JK.count, 1); case .suika: return (SK.count, 1); case .pool: return (PoolCodec.count, 1); case .tilePush: return (TP.count, 1) }
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

/// Tile Push message layout: 16 cells of your map (row-major, top row first), 16 of the opponent's, then the tile in hand.
/// 0 face down, 1 the opponent's picture, 2 the blue cat joker, 3…8 your pictures, 9…12 pictures not known yet to be
/// yours or theirs (same number = same picture).
enum TP {
    static let mine = 0, opp = 16, hand = 32, count = 33
    static let n = 4
}

/// Jackaroo message layout (cells): colours 0 none, 1 green, 2 red, 3 blue, 4 orange.
enum JK {
    static let track = 0        // 76 track holes
    static let lanes = 76       // + 4*seat + slot
    static let homes = 92       // + 4*seat + slot
    static let seats = 108      // colour of each seat 0..3
    static let hand = 112       // up to 5 cards: 1 A, 2…10, 11 J, 12 Q, 13 K
    static let playable = 117   // 1 when that card is white (the game lets you play it)
    static let discard = 122    // 1 while the big DISCARD banner is on the board
    static let count = 123
    static let rankNames = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
}



/// Pool message layout (cells, every value 0…13 so it fits the Darwin transport).
/// Positions are on the playing surface in half-pixels of a 1180×2556 screen, origin at the top-left
/// cushion nose (207.5, 584); x·3200 + y packed as 6 base-14 digits.
/// me: 0 open table, 1 you have solids, 2 stripes, 3 your group is cleared (play the 8).
enum PoolCodec {
    static let flags = 0          // bit0 table read cleanly, bit1 the game's aim circle is on screen, bit2 power bar is being pulled
    static let aim = 1            // 6 digits: centre of the game's aim (ghost-ball) circle
    static let balls = 7          // + 7*id: present (0/1) + 6 digits; id 0 = cue ball, 1…15
    static let myLeft = 119       // balls left in your group (from the bar)
    static let oppLeft = 120
    static let power = 121        // 2 digits: how far the power bar is pulled, 0…100 %
    static let objDir = 123       // 3 digits: direction of the game's line from the hit ball, degrees × 7; 13,13,13 = none
                                  // (it was flag bit3, but a cell holds 0…13: all four flags made 15 and lost the aim bit
                                  // exactly while you pulled with the line seen)
    static let readMs = 126       // 2 digits: how long one screen reading takes (ms, averaged; set once a second)
    static let readRate = 128     // 2 digits: readings per second
    static let spinX = 130        // where the red mark sits on the spin icon (bottom right): 0…12, 6 = centre, 13 = not seen
    static let spinY = 131        //   (x: left → right, y: top = follow … bottom = draw)
    static let menu = 132         // 1 = the spin menu is open (its big cue ball covers the table: nothing on it is read)
    static let count = 133
    /// spin as -1…1 on each axis (nil when the icon wasn't read)
    static func spin(_ cells: [Int]) -> (x: Double, y: Double)? {
        guard cells.count > spinY, cells[spinX] <= 12, cells[spinY] <= 12 else { return nil }
        return (Double(cells[spinX] - 6) / 6, Double(cells[spinY] - 6) / 6)
    }
    static func two(_ cells: [Int], _ at: Int) -> Int { cells[at] * 14 + cells[at + 1] }
    static func dir(_ cells: [Int]) -> Double? {
        let q = cells[objDir] * 196 + cells[objDir + 1] * 14 + cells[objDir + 2]
        guard q < 2520 else { return nil }
        return Double(q) / 7 * Double.pi / 180
    }
    static let originX = 207.5, originY = 584.0, width = 759.0, height = 1551.0

    static func put(_ cells: inout [Int], _ at: Int, _ x: Double, _ y: Double) {
        let qx = max(0, min(1599, Int(((x - originX) * 2).rounded()))), qy = max(0, min(3199, Int(((y - originY) * 2).rounded())))
        var v = qx * 3200 + qy
        for k in 0..<6 { cells[at + 5 - k] = v % 14; v /= 14 }
    }
    static func get(_ cells: [Int], _ at: Int) -> (x: Double, y: Double) {
        var v = 0
        for k in 0..<6 { v = v * 14 + cells[at + k] }
        return (originX + Double(v / 3200) / 2, originY + Double(v % 3200) / 2)
    }
}
