import AppKit
import BarnataCore
import Foundation

/// Menu bar images. Status icons are SF Symbols that `app.status_icons` can override with files.
/// Layer icons are SF Symbols from `IconCatalog`; a value outside the pool draws the warning symbol.
@MainActor
public final class IconStore {
    /// Every image is fitted into this square so the status item never changes width
    public static let imageSize: CGFloat = 18

    private static let symbolNames: [IconResolver.StatusIcon: String] = [
        .normal: "keyboard.badge.ellipsis",
        .crashed: "exclamationmark.triangle.fill",
        .paused: "sleep",
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
            guard let symbol = preset?.iconSymbol(forLayer: layer) else { return statusImage(.normal) }
            guard IconCatalog.contains(symbol) else { return symbolImage(IconCatalog.warningSymbol) }
            return symbolImage(symbol) ?? statusImage(.normal)
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
        IconStore.symbolNames[icon].flatMap { symbolImage($0) }
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let key = "symbol:\(name)"
        if let cached = cache[key] { return cached }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: name) else { return nil }

        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        ) ?? image
        configured.isTemplate = true
        resize(configured)
        cache[key] = configured
        return configured
    }

    /// Fit inside the square, so a wide icon shrinks instead of widening the status item
    private func resize(_ image: NSImage) {
        let longest = Swift.max(image.size.width, image.size.height)
        guard longest > 0, longest != IconStore.imageSize else { return }
        let scale = IconStore.imageSize / longest
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}
