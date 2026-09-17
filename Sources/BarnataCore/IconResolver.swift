import Foundation

/// Turns status states into icon files under the config directory. Layer icons are
/// SF Symbols from `IconCatalog` and never touch the filesystem.
public struct IconResolver: Sendable, Equatable {
    public enum StatusIcon: String, CaseIterable, Sendable {
        case normal = "default"
        case crashed
        case paused
        case reloading
    }

    public static let iconsDirectoryName = "icons"
    private static let templateSuffix = "Template"

    public let iconsDirectory: URL
    public let statusIconsDirectory: URL?

    public init(configDirectory: URL, statusIcons: String? = nil) {
        let icons = configDirectory.appending(path: IconResolver.iconsDirectoryName)
        self.iconsDirectory = icons
        self.statusIconsDirectory = statusIcons.map { path in
            path.hasPrefix("/") ? URL(fileURLWithPath: path) : icons.appending(path: path)
        }
    }

    public init(config: Config, configURL: URL) {
        self.init(configDirectory: configURL.deletingLastPathComponent(), statusIcons: config.app.statusIcons)
    }

    /// Override file for a status icon, nil when the app should use its bundled copy
    public func statusIconURL(_ icon: StatusIcon, fileManager: FileManager = .default) -> URL? {
        guard let statusIconsDirectory,
              let entries = try? fileManager.contentsOfDirectory(atPath: statusIconsDirectory.path)
        else { return nil }

        let match = entries.sorted().first { entry in
            var stem = (entry as NSString).deletingPathExtension
            if stem.hasSuffix(IconResolver.templateSuffix) {
                stem = String(stem.dropLast(IconResolver.templateSuffix.count))
            }
            return stem == icon.rawValue
        }
        return match.map { statusIconsDirectory.appending(path: $0) }
    }

    /// Apple's naming convention: a file named `<name>Template.png` is a template image
    public static func isTemplate(fileName: String) -> Bool {
        (fileName as NSString).deletingPathExtension.hasSuffix(templateSuffix)
    }

    public static func isTemplate(_ url: URL) -> Bool {
        isTemplate(fileName: url.lastPathComponent)
    }
}
