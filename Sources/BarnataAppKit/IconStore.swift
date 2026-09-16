import AppKit
import BarnataCore
import Foundation

/// Menu bar images. Bundled status icons are SF Symbols; `app.status_icons` overrides them with files.
@MainActor
public final class IconStore {
    public static let imageHeight: CGFloat = 18

    private static let symbolNames: [IconResolver.StatusIcon: String] = [
        .normal: "keyboard",
        .crashed: "exclamationmark.triangle.fill",
        .paused: "pause.circle",
        .reloading: "arrow.triangle.2.circlepath",
    ]

    public var resolver: IconResolver?

    private var cache: [String: NSImage] = [:]

    public init() {}

    public func invalidate() {
        cache = [:]
    }

    public func image(for presentation: StatusPresentation, preset: Preset?) -> NSImage? {
        switch presentation {
        case .status(let icon):
            return statusImage(icon)
        case .layer(let layer):
            guard let preset, let url = resolver?.layerIconURL(forLayer: layer, in: preset),
                  let image = fileImage(at: url)
            else { return statusImage(.normal) }
            return image
        }
    }

    public func statusImage(_ icon: IconResolver.StatusIcon) -> NSImage? {
        if let override = resolver?.statusIconURL(icon), let image = fileImage(at: override) { return image }
        return symbolImage(icon)
    }

    // MARK: - Loading

    private func fileImage(at url: URL) -> NSImage? {
        if let cached = cache[url.path] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = IconResolver.isTemplate(url)
        resize(image)
        cache[url.path] = image
        return image
    }

    private func symbolImage(_ icon: IconResolver.StatusIcon) -> NSImage? {
        let key = "symbol:\(icon.rawValue)"
        if let cached = cache[key] { return cached }
        guard let name = IconStore.symbolNames[icon],
              let image = NSImage(systemSymbolName: name, accessibilityDescription: icon.rawValue)
        else { return nil }

        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        ) ?? image
        configured.isTemplate = true
        cache[key] = configured
        return configured
    }

    /// Menu bar images must be small; keep the aspect ratio and pin the height
    private func resize(_ image: NSImage) {
        guard image.size.height > 0, image.size.height != IconStore.imageHeight else { return }
        let scale = IconStore.imageHeight / image.size.height
        image.size = NSSize(width: image.size.width * scale, height: IconStore.imageHeight)
    }
}
