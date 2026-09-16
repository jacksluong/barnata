import AppKit
import BarnataCore
import Foundation

/// Renders a `[MenuEntry]` tree into the real status item and menu. Holds no app state of its own.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    public static let spinnerDelay: TimeInterval = 0.4

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let iconStore = IconStore()
    private var spinner: NSProgressIndicator?
    private var spinnerTimer: Timer?
    private var currentImage: NSImage?

    public var onAction: ((MenuAction) -> Void)?
    public var onMenuWillOpen: (() -> Void)?

    public var resolver: IconResolver? {
        get { iconStore.resolver }
        set {
            iconStore.resolver = newValue
            iconStore.invalidate()
        }
    }

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
    }

    public func render(_ state: MenuState, preset: Preset?) {
        currentImage = iconStore.image(for: state.presentation, preset: preset)
        statusItem.button?.toolTip = "Barnata: \(state.title)"

        if state.isTransitioning {
            startSpinnerTimer()
        } else {
            stopSpinner()
        }

        menu.removeAllItems()
        for entry in MenuBuilder.entries(for: state) {
            menu.addItem(makeItem(entry))
        }
    }

    public func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    // MARK: - Building AppKit objects

    private func makeItem(_ entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return NSMenuItem.separator()

        case .label(let text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item

        case .item(let model):
            return configure(NSMenuItem(), with: model)

        case .submenu(let model, let children):
            let item = configure(NSMenuItem(), with: model)
            item.action = nil
            item.target = nil
            let submenu = NSMenu(title: model.title)
            for child in children { submenu.addItem(makeItem(child)) }
            item.submenu = submenu
            return item
        }
    }

    private func configure(_ item: NSMenuItem, with model: MenuItem) -> NSMenuItem {
        item.title = model.title
        item.isEnabled = model.isEnabled
        item.state = model.isChecked ? .on : .off
        item.keyEquivalent = model.keyEquivalent
        item.indentationLevel = model.isIndented ? 1 : 0
        item.representedObject = MenuActionBox(model.action)

        if model.action != .none, model.isEnabled {
            item.action = #selector(invoke(_:))
            item.target = self
        }
        return item
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuActionBox else { return }
        onAction?(box.action)
    }

    // MARK: - Transition spinner

    /// Short transitions keep the previous icon, so the spinner only appears after a delay
    private func startSpinnerTimer() {
        applyImage()
        guard spinner == nil, spinnerTimer == nil else { return }
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: StatusItemController.spinnerDelay, repeats: false) { _ in
            MainActor.assumeIsolated { self.showSpinner() }
        }
    }

    private func showSpinner() {
        spinnerTimer = nil
        guard spinner == nil, let button = statusItem.button else { return }

        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        button.image = nil
        button.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 16),
            indicator.heightAnchor.constraint(equalToConstant: 16),
        ])
        indicator.startAnimation(nil)
        spinner = indicator
    }

    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        spinner?.stopAnimation(nil)
        spinner?.removeFromSuperview()
        spinner = nil
        applyImage()
    }

    private func applyImage() {
        guard spinner == nil else { return }
        statusItem.button?.image = currentImage
    }
}

/// NSMenuItem.representedObject needs a class, and MenuAction is an enum
private final class MenuActionBox {
    let action: MenuAction

    init(_ action: MenuAction) {
        self.action = action
    }
}
