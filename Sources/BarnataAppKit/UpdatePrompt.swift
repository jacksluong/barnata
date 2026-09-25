import AppKit
import Foundation

/// The dialogs the update flow shows. A menu bar app has no window to hang a sheet on, so
/// both run as application-modal alerts.
@MainActor
public enum UpdatePrompt {
    public enum Choice {
        case update
        case later
    }

    static let notesSize = NSSize(width: 360, height: 160)

    public static func ask(about update: AvailableUpdate, currentVersion: String) -> Choice {
        let alert = NSAlert()
        alert.messageText = "A new update is available"
        alert.informativeText = "Good news! Barnata v\(update.version) is available (you have v\(currentVersion))."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later").keyEquivalent = "\u{1b}"
        if let notes = update.notes {
            alert.accessoryView = notesView(notes)
        }

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .update : .later
    }

    public static func reportFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The update did not finish"
        alert.informativeText = "\(message)\n\nYou can also run this in Terminal:\nbrew upgrade --cask \(UpdateInstaller.caskToken)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show Log")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { UpdateInstaller.revealLog() }
    }

    /// Release notes, scrollable and selectable, sized so a long changelog does not stretch the alert
    private static func notesView(_ notes: String) -> NSView {
        let text = NSTextView(frame: NSRect(origin: .zero, size: notesSize))
        text.string = notes
        text.isEditable = false
        text.drawsBackground = false
        text.font = .preferredFont(forTextStyle: .body)
        text.textContainerInset = NSSize(width: 4, height: 4)

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: notesSize))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        return scroll
    }
}
