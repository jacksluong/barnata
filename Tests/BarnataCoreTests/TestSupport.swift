import Foundation
import XCTest

@testable import BarnataCore

let testHome = URL(fileURLWithPath: "/Users/test")
let testConfigDirectory = URL(fileURLWithPath: "/Users/test/.config/barnata")

func parseConfig(_ text: String) throws -> Config {
    try ConfigLoader.parse(text, directory: testConfigDirectory, home: testHome)
}

/// Asserts that `body` throws a ConfigError and hands it to `check`
func assertConfigError(
    _ text: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ check: (ConfigError) -> Void
) {
    do {
        let config = try parseConfig(text)
        XCTFail("expected a ConfigError, got \(config)", file: file, line: line)
    } catch let error as ConfigError {
        check(error)
    } catch {
        XCTFail("expected a ConfigError, got \(error)", file: file, line: line)
    }
}

let fullConfigExample = """
[app]
launch_at_login = true
show_dock_icon = false

[defaults]
autorestart_on_crash = false

[defaults.layer_icons]
base     = "base.png"
typing   = "typing.png"
arrows   = "arrows.png"
numbers  = "numbers.png"
launcher = "launcher.png"
system   = "system.png"
navcode  = "navcode.png"
modnums  = "modnums.png"
nohrm    = "nohrm.png"
"*"      = "default.png"

[presets."Default"]
kanata_config = "~/.config/kanata/example.kbd"
autorun = true
"""
