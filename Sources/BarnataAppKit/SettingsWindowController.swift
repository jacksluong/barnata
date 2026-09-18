import AppKit
import SwiftUI

/// The single settings window. The tab strip is a real preference-style `NSToolbar`, the way
/// System Settings and Finder Settings draw theirs; SwiftUI only fills the content below it.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let frameAutosaveName = "BarnataSettings"
    static let defaultContentSize = NSSize(width: 720, height: 520)
    static let minimumContentSize = NSSize(width: 660, height: 420)

    public let model: SettingsModel

    private var window: NSWindow?

    public init(model: SettingsModel) {
        self.model = model
        super.init()
    }

    public func show() {
        let window = window ?? makeWindow()
        self.window = window

        model.reload()
        model.refreshSystemState()
        model.startPolling()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowController.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Barnata Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.contentMinSize = SettingsWindowController.minimumContentSize
        // The hosting controller shrinks the window to the SwiftUI view's own fitting size,
        // so the content size is set back afterwards rather than in the initial frame
        window.setContentSize(SettingsWindowController.defaultContentSize)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let toolbar = NSToolbar(identifier: "BarnataSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = model.tab.itemIdentifier
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        window.center()
        // Centered first, so the very first open lands somewhere sensible
        window.setFrameAutosaveName(SettingsWindowController.frameAutosaveName)
        window.setFrameUsingName(SettingsWindowController.frameAutosaveName)
        return window
    }

    // MARK: - NSToolbarDelegate

    private var identifiers: [NSToolbarItem.Identifier] { SettingsTab.allCases.map(\.itemIdentifier) }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(itemIdentifier: identifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(itemIdentifier: sender.itemIdentifier) else { return }
        model.tab = tab
        window?.toolbar?.selectedItemIdentifier = tab.itemIdentifier
    }
}

extension SettingsTab {
    var itemIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }

    init?(itemIdentifier: NSToolbarItem.Identifier) {
        self.init(rawValue: itemIdentifier.rawValue)
    }
}
