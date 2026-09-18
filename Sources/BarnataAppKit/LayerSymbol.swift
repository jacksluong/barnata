import AppKit
import Foundation

/// Layer icons are SF Symbols, and a name is valid whenever this Mac can draw it. `IconCatalog`
/// is only what the picker offers first, so a name from outside it is still a working icon.
public enum LayerSymbol {
    public static func isAvailable(_ symbol: String) -> Bool {
        cache.isAvailable(symbol)
    }

    /// Layer names in `layerIcons` whose symbol this Mac cannot draw, sorted
    public static func unavailable(in layerIcons: [String: String]) -> [String] {
        layerIcons.filter { !isAvailable($0.value) }.keys.sorted()
    }
}

/// Resolving a symbol name is slow enough to matter while typing in the picker
private final class SymbolCache: @unchecked Sendable {
    private let lock = NSLock()
    private var known: [String: Bool] = [:]

    func isAvailable(_ symbol: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let cached = known[symbol] { return cached }
        let available = !symbol.isEmpty
            && NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        known[symbol] = available
        return available
    }
}

private let cache = SymbolCache()
