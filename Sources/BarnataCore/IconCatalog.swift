import Foundation

/// The fixed pool of SF Symbols a layer icon may be set to. Values outside the pool are invalid
/// and render as `IconCatalog.warningSymbol` everywhere the icon would have appeared.
public enum IconCatalog {
    public static let warningSymbol = "exclamationmark.triangle.fill"

    public struct Group: Sendable, Equatable, Identifiable {
        public let name: String
        public let symbols: [String]

        public init(name: String, symbols: [String]) {
            self.name = name
            self.symbols = symbols
        }

        public var id: String { name }
    }

    public static let groups: [Group] = [
        Group(name: "Keyboard", symbols: [
            "keyboard", "keyboard.fill", "keyboard.badge.ellipsis", "keyboard.chevron.compact.down",
            "command", "command.circle", "command.circle.fill", "command.square", "command.square.fill",
            "option", "control", "shift", "shift.fill", "capslock", "capslock.fill",
            "escape", "delete.left", "delete.left.fill", "delete.right", "return",
            "globe", "textformat", "textformat.abc", "textformat.size", "character", "character.cursor.ibeam",
            "text.cursor", "underline", "bold", "italic",
        ]),
        Group(name: "Arrows", symbols: [
            "arrow.up", "arrow.down", "arrow.left", "arrow.right",
            "arrow.up.arrow.down", "arrow.left.arrow.right", "arrow.up.left", "arrow.up.right",
            "arrow.down.left", "arrow.down.right", "arrow.turn.down.left", "arrow.uturn.left",
            "arrow.uturn.backward", "arrow.clockwise", "arrow.counterclockwise",
            "arrow.up.left.and.arrow.down.right", "arrow.down.right.and.arrow.up.left",
            "arrow.triangle.2.circlepath", "arrow.triangle.branch", "arrow.triangle.merge",
            "chevron.up", "chevron.down", "chevron.left", "chevron.right", "chevron.up.chevron.down",
            "arrowshape.up", "arrowshape.down", "arrowshape.left", "arrowshape.right",
        ]),
        Group(name: "Numbers", symbols: [
            "number", "number.circle", "number.circle.fill", "number.square", "number.square.fill",
            "textformat.123", "list.number", "plus", "minus", "plusminus", "multiply", "divide", "equal",
            "percent", "function", "sum", "x.squareroot", "lessthan", "greaterthan",
            "0.circle", "1.circle", "2.circle", "3.circle", "4.circle",
            "5.circle", "6.circle", "7.circle", "8.circle", "9.circle",
        ]),
        Group(name: "System", symbols: [
            "gear", "gearshape", "gearshape.fill", "gearshape.2", "wrench", "wrench.and.screwdriver",
            "hammer", "screwdriver", "slider.horizontal.3", "switch.2", "dial.min", "dial.max",
            "power", "bolt", "bolt.fill", "bolt.circle", "bolt.horizontal",
            "cpu", "memorychip", "desktopcomputer", "laptopcomputer", "display", "externaldrive",
            "internaldrive", "server.rack", "terminal", "terminal.fill", "curlybraces",
            "chevron.left.forwardslash.chevron.right", "ladybug", "hare", "tortoise",
        ]),
        Group(name: "Apps", symbols: [
            "square.grid.2x2", "square.grid.2x2.fill", "square.grid.3x3", "square.grid.3x3.fill",
            "rectangle.grid.2x2", "rectangle.3.group", "app", "app.fill", "macwindow",
            "magnifyingglass", "magnifyingglass.circle", "magnifyingglass.circle.fill",
            "sparkles", "wand.and.stars", "paperplane", "paperplane.fill",
            "folder", "folder.fill", "tray", "tray.full", "archivebox", "doc", "doc.text", "doc.on.doc",
            "link", "book", "books.vertical", "calendar", "clock", "alarm", "timer", "stopwatch",
        ]),
        Group(name: "Media", symbols: [
            "play", "play.fill", "pause", "pause.fill", "playpause", "playpause.fill", "stop", "stop.fill",
            "forward", "forward.fill", "backward", "backward.fill", "forward.end.fill", "backward.end.fill",
            "speaker.wave.2", "speaker.wave.2.fill", "speaker.slash", "speaker.slash.fill",
            "music.note", "headphones", "mic", "mic.fill", "mic.slash", "video", "video.fill", "camera",
        ]),
        Group(name: "Shapes", symbols: [
            "circle", "circle.fill", "square", "square.fill", "triangle", "triangle.fill",
            "diamond", "diamond.fill", "hexagon", "hexagon.fill", "seal", "seal.fill",
            "star", "star.fill", "heart", "heart.fill", "flag", "flag.fill",
            "bookmark", "bookmark.fill", "tag", "tag.fill", "pin", "pin.fill",
            "smallcircle.filled.circle", "dot.circle", "scope", "target",
        ]),
        Group(name: "Marks", symbols: [
            "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.seal",
            "xmark", "xmark.circle", "xmark.circle.fill", "questionmark", "questionmark.circle",
            "exclamationmark", "exclamationmark.circle", "exclamationmark.triangle",
            "exclamationmark.triangle.fill", "info.circle", "lock", "lock.fill", "lock.open",
            "eye", "eye.slash", "hand.raised", "hand.raised.fill", "bell", "bell.fill", "bell.slash",
        ]),
        Group(name: "Nature", symbols: [
            "moon", "moon.fill", "moon.stars", "sun.max", "sun.max.fill", "sunrise", "sunset",
            "cloud", "cloud.fill", "drop", "drop.fill", "flame", "flame.fill",
            "leaf", "leaf.fill", "snowflake", "wind", "tornado", "globe.americas", "map", "location",
        ]),
    ]

    public static let symbols: [String] = groups.flatMap(\.symbols)

    private static let allowed = Set(symbols)

    public static func contains(_ symbol: String) -> Bool { allowed.contains(symbol) }

    /// Layer names in `preset` whose icon is set to something outside the pool
    public static func invalidLayerIcons(in preset: Preset) -> [String] {
        preset.layerIcons.filter { !contains($0.value) }.keys.sorted()
    }
}
