import SwiftUI

/// 5×7 dot-matrix type, drawn dot by dot. No font files, no licensing.
struct DotText: View {
    let text: String
    var pitch: CGFloat = 4
    var color: Color = Theme.ink
    var ghost = false

    init(_ text: String, pitch: CGFloat = 4, color: Color = Theme.ink, ghost: Bool = false) {
        self.text = text
        self.pitch = pitch
        self.color = color
        self.ghost = ghost
    }

    var body: some View {
        let chars = Array(text.uppercased())
        let columns = max(chars.count * 6 - 1, 0)
        Canvas { ctx, _ in
            let d = pitch * 0.78
            let inset = (pitch - d) / 2
            var lit = Path()
            var off = Path()
            for (i, ch) in chars.enumerated() {
                let glyph = DotFont.glyph(ch)
                for r in 0..<7 {
                    for c in 0..<5 {
                        let rect = CGRect(x: CGFloat(i * 6 + c) * pitch + inset, y: CGFloat(r) * pitch + inset, width: d, height: d)
                        if glyph[r][c] { lit.addEllipse(in: rect) } else if ghost { off.addEllipse(in: rect) }
                    }
                }
            }
            if ghost { ctx.fill(off, with: .color(color.opacity(0.09))) }
            ctx.fill(lit, with: .color(color))
        }
        .frame(width: CGFloat(columns) * pitch, height: 7 * pitch)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// Bitmap art drawn as dots — icons and pets. See `Glyphs` for the key.
struct DotSprite: View {
    let rows: [String]
    var pitch: CGFloat = 3
    var color: Color = Theme.ink
    var accent: Color = Theme.red
    var ghost = false
    var dimmed = false

    var body: some View {
        let width = rows.map(\.count).max() ?? 0
        Canvas { ctx, _ in
            let d = pitch * 0.8
            let inset = (pitch - d) / 2
            var ink = Path(), half = Path(), red = Path(), off = Path()
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(c) * pitch + inset, y: CGFloat(r) * pitch + inset, width: d, height: d)
                    switch ch {
                    case "#": ink.addEllipse(in: rect)
                    case "-": half.addEllipse(in: rect)
                    case "o": red.addEllipse(in: rect)
                    default: if ghost { off.addEllipse(in: rect) }
                    }
                }
            }
            let main = dimmed ? Theme.ghost : color
            ctx.fill(off, with: .color(color.opacity(0.08)))
            ctx.fill(ink, with: .color(main))
            ctx.fill(half, with: .color(main.opacity(0.45)))
            ctx.fill(red, with: .color(dimmed ? Theme.ghost : accent))
        }
        .frame(width: CGFloat(width) * pitch, height: CGFloat(rows.count) * pitch)
        .accessibilityHidden(true)
    }
}

enum DotFont {
    static func glyph(_ ch: Character) -> [[Bool]] {
        table[ch] ?? table["?"]!
    }

    private static let table: [Character: [[Bool]]] = raw.mapValues { rows in
        rows.map { row in row.map { $0 == "#" } }
    }

    private static let raw: [Character: [String]] = [
        "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
        "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
        "C": [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
        "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
        "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
        "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
        "G": [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
        "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
        "I": [" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
        "J": ["  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "],
        "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
        "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
        "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
        "N": ["#   #", "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #"],
        "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
        "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
        "Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
        "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
        "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
        "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
        "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
        "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
        "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", " # # "],
        "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
        "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
        "Z": ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
        "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
        "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
        "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
        "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
        "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
        "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
        "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
        "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
        "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
        "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
        " ": ["     ", "     ", "     ", "     ", "     ", "     ", "     "],
        ".": ["     ", "     ", "     ", "     ", "     ", "     ", "  #  "],
        ":": ["     ", "  #  ", "     ", "     ", "     ", "  #  ", "     "],
        "-": ["     ", "     ", "     ", " ### ", "     ", "     ", "     "],
        "+": ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
        "/": ["    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "],
        "%": ["##   ", "##  #", "   # ", "  #  ", " #   ", "#  ##", "   ##"],
        "!": ["  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  "],
        "?": [" ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  "],
        ",": ["     ", "     ", "     ", "     ", "     ", "  #  ", " #   "],
        "'": ["  #  ", "  #  ", "     ", "     ", "     ", "     ", "     "],
        "_": ["     ", "     ", "     ", "     ", "     ", "     ", "#####"],
        ">": [" #   ", "  #  ", "   # ", "    #", "   # ", "  #  ", " #   "],
        "<": ["   # ", "  #  ", " #   ", "#    ", " #   ", "  #  ", "   # "],
    ]
}
