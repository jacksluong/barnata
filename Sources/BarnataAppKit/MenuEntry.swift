import Foundation

/// Everything the menu can ask the app to do. Carries its own payload so the renderer stays dumb.
public enum MenuAction: Sendable, Hashable {
    case none
    case startPreset(String)
    case stopKanata
    case restartKanata
    case switchLayer(String)
    case reloadConfig
    case nextConfigFile
    case previousConfigFile
    case openKanataLog
    case openPreferences
    case quit
}

public struct MenuItem: Sendable, Equatable {
    public var title: String
    public var action: MenuAction
    public var isEnabled: Bool
    public var isChecked: Bool
    public var keyEquivalent: String
    public var isIndented: Bool

    public init(
        title: String,
        action: MenuAction = .none,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        keyEquivalent: String = "",
        isIndented: Bool = false
    ) {
        self.title = title
        self.action = action
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.keyEquivalent = keyEquivalent
        self.isIndented = isIndented
    }
}

/// The menu as plain values, built before any AppKit object exists
public enum MenuEntry: Sendable, Equatable {
    case label(String)
    case separator
    case item(MenuItem)
    case submenu(MenuItem, [MenuEntry])

    public var item: MenuItem? {
        switch self {
        case .item(let item), .submenu(let item, _): item
        case .label, .separator: nil
        }
    }

    public var children: [MenuEntry] {
        if case .submenu(_, let children) = self { return children }
        return []
    }
}

extension Array where Element == MenuEntry {
    /// Depth-first walk, used by the renderer and by the tests
    public var allItems: [MenuItem] {
        flatMap { entry -> [MenuItem] in
            guard let item = entry.item else { return [] }
            return [item] + entry.children.allItems
        }
    }

    public func item(titled title: String) -> MenuItem? {
        allItems.first { $0.title == title }
    }

    public func submenu(titled title: String) -> [MenuEntry]? {
        for entry in self {
            if case .submenu(let item, let children) = entry, item.title == title { return children }
        }
        return nil
    }
}
