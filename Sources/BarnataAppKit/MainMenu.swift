import AppKit

/// A menu bar app draws no menu bar, but NSApplication still routes key equivalents through
/// `mainMenu`. Without these, text fields in the settings window get no copy, paste, or undo.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let root = NSMenu()
        root.addItem(appItem())
        root.addItem(editItem())
        return root
    }

    private static func appItem() -> NSMenuItem {
        let menu = NSMenu(title: "Barnata")
        let about = menu.addItem(withTitle: "About Barnata", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Barnata", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: "Quit Barnata", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item(menu)
    }

    private static func editItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return item(menu)
    }

    private static func item(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }
}
