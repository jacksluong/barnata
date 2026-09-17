import BarnataCore
import Foundation
import XCTest

@testable import BarnataAppKit

@MainActor
final class SettingsModelTests: XCTestCase {
    private var root: URL!
    private var configURL: URL!
    private var stopCount = 0

    override func setUp() async throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        configURL = root.appending(path: "barnata/config.toml")
        try FileManager.default.createDirectory(at: root.appending(path: "barnata"), withIntermediateDirectories: true)
        stopCount = 0
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(_ toml: String = "") throws -> SettingsModel {
        try toml.write(to: configURL, atomically: true, encoding: .utf8)
        return SettingsModel(
            configURL: configURL,
            setup: SetupActions(),
            actions: SettingsActions(
                installDriver: { $0(.success) },
                activateDriver: { $0(.success) },
                stopKanata: { [weak self] completion in
                    self?.stopCount += 1
                    completion(.success)
                },
                setDockIconVisible: { _ in },
                configDidChange: { _ in }
            )
        )
    }

    private func writeConfigFile(named name: String, layers: [String]) throws -> URL {
        let url = root.appending(path: name)
        let text = layers.map { "(deflayer \($0) a b c)" }.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func text() throws -> String {
        try String(contentsOf: configURL, encoding: .utf8)
    }

    // MARK: - References

    func testAddingAFileStoresOnlyAReferenceToIt() throws {
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base", "typing"])
        let model = try makeModel()
        model.add([kbd])

        XCTAssertEqual(model.entries.map(\.name), ["home"])
        XCTAssertEqual(model.entries.first?.paths, [kbd.standardizedFileURL.path])
        XCTAssertEqual(model.layers, ["base", "typing"])

        // Nothing is copied next to config.toml
        let stored = try FileManager.default.contentsOfDirectory(atPath: configURL.deletingLastPathComponent().path)
        XCTAssertEqual(stored, ["config.toml"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: kbd.path))
    }

    func testAddingTwoFilesOfTheSameNameKeepsBothReferences() throws {
        let first = try writeConfigFile(named: "home.kbd", layers: ["base"])
        try FileManager.default.createDirectory(at: root.appending(path: "nested"), withIntermediateDirectories: true)
        let second = try writeConfigFile(named: "nested/home.kbd", layers: ["other"])

        let model = try makeModel()
        model.add([first, second])
        XCTAssertEqual(model.entries.map(\.name), ["home", "home 2"])
    }

    func testTheSelectionMovesToTheFileJustAdded() throws {
        let first = try writeConfigFile(named: "a.kbd", layers: ["base"])
        let second = try writeConfigFile(named: "b.kbd", layers: ["other"])

        let model = try makeModel()
        model.add([first])
        model.add([second])
        XCTAssertEqual(model.selection, "b")
        XCTAssertEqual(model.layers, ["other"])
    }

    func testRenamingWritesTheNewLabelAndKeepsTheReference() throws {
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base"])
        let model = try makeModel()
        model.add([kbd])
        model.rename(model.entries[0], to: "Home Row")

        XCTAssertEqual(model.entries.map(\.name), ["Home Row"])
        XCTAssertEqual(model.selection, "Home Row")
        XCTAssertTrue(try text().contains("[presets.\"Home Row\"]"))
    }

    func testRenamingToANameAlreadyTakenIsRefused() throws {
        let first = try writeConfigFile(named: "a.kbd", layers: ["base"])
        let second = try writeConfigFile(named: "b.kbd", layers: ["base"])
        let model = try makeModel()
        model.add([first, second])

        model.rename(model.entries[0], to: "b")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.entries.map(\.name), ["a", "b"])
    }

    func testDeletingRemovesTheReferenceButNotTheFile() throws {
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base"])
        let model = try makeModel()
        model.add([kbd])
        model.delete(model.entries[0])

        XCTAssertEqual(model.entries, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: kbd.path))
        XCTAssertEqual(stopCount, 0)
    }

    func testDeletingTheRunningConfigStopsKanataFirst() throws {
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base"])
        let model = try makeModel()
        model.add([kbd])
        model.activePresetName = "home"
        model.delete(model.entries[0])

        XCTAssertEqual(stopCount, 1)
    }

    func testAMissingFileIsFlaggedRatherThanDropped() throws {
        let model = try makeModel("""
        [presets."Gone"]
        kanata_config = "/nope/missing.kbd"
        """)
        XCTAssertEqual(model.entries.map(\.name), ["Gone"])
        XCTAssertEqual(model.entries[0].missingPaths, ["/nope/missing.kbd"])
        XCTAssertEqual(model.layers, [])
    }

    func testTheWindowOpensOnGeneral() throws {
        XCTAssertEqual(try makeModel().tab, .general)
        XCTAssertEqual(SettingsTab.allCases.map(\.title), ["General", "Configs"])
    }

    // MARK: - Icons

    func testSettingAnIconWritesASymbolNameIntoThePreset() throws {
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base"])
        let model = try makeModel()
        model.add([kbd])
        model.setIcon("command", for: "base", in: model.entries[0])

        XCTAssertEqual(model.entries[0].layerIcons, ["base": "command"])
        XCTAssertTrue(try text().contains("[presets.\"home\".layer_icons]"))
    }

    func testClearingAnIconRemovesIt() throws {
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base"])
        let model = try makeModel()
        model.add([kbd])
        model.setIcon("command", for: "base", in: model.entries[0])
        model.setIcon(nil, for: "base", in: model.entries[0])

        XCTAssertEqual(model.entries[0].layerIcons, [:])
    }

    func testIconsFromTheOldFileBasedSchemeAreReportedAsInvalid() throws {
        let model = try makeModel("""
        [presets."Old"]
        kanata_config = "/nope/missing.kbd"

        [presets."Old".layer_icons]
        base = "baseTemplate.png"
        typing = "keyboard"
        """)
        XCTAssertEqual(model.entries[0].invalidIconLayers, ["base"])
        XCTAssertTrue(model.entries[0].hasInvalidIcons)
    }

    func testAnIconEditDoesNotDisturbTheRestOfTheFile() throws {
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base"])
        let model = try makeModel("""
        # my config
        [app]
        show_dock_icon = false   # keep this comment
        """)
        model.add([kbd])
        model.setIcon("command", for: "base", in: model.entries[0])

        let written = try text()
        XCTAssertTrue(written.contains("# my config"))
        XCTAssertTrue(written.contains("show_dock_icon = false   # keep this comment"))
    }

    // MARK: - Uninstall

    func testTheConfirmationWordIsAllCaps() {
        XCTAssertEqual(SettingsModel.uninstallConfirmationWord, "UNINSTALL")
    }

    func testRenamingCommitsWhenTheFieldLosesFocusToo() throws {
        // The view calls the same entry point from onSubmit and from a focus change
        let kbd = try writeConfigFile(named: "home.kbd", layers: ["base"])
        let model = try makeModel()
        model.add([kbd])
        model.rename(model.entries[0], to: "  Padded  ")

        XCTAssertEqual(model.entries.map(\.name), ["Padded"])
        XCTAssertEqual(model.selection, "Padded")
    }
}

final class UniqueNameTests: XCTestCase {
    func testTheFileStemBecomesTheLabel() {
        XCTAssertEqual(SettingsModel.uniqueName(from: URL(fileURLWithPath: "/tmp/example.kbd"), taken: []), "example")
    }

    func testACollisionGetsTheNextFreeNumber() {
        let url = URL(fileURLWithPath: "/tmp/example.kbd")
        XCTAssertEqual(SettingsModel.uniqueName(from: url, taken: ["example"]), "example 2")
        XCTAssertEqual(SettingsModel.uniqueName(from: url, taken: ["example", "example 2"]), "example 3")
    }
}
