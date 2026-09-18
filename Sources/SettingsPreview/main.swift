import AppKit
import BarnataAppKit
import BarnataCore

let application = NSApplication.shared
application.setActivationPolicy(.regular)

let url = ConfigLoader.defaultURL()
let model = SettingsModel(
    configURL: url,
    setup: SetupActions(),
    actions: SettingsActions(
        installDriver: { $0(.success) },
        activateDriver: { $0(.success) },
        stopKanata: { $0(.success) },
        setDockIconVisible: { _ in },
        showUpdate: {},
        configDidChange: { _ in }
    )
)
let controller = SettingsWindowController(model: model)
controller.show()
application.run()
