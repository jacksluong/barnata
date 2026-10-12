import Foundation

/// A published release newer than the running app
public struct AvailableUpdate: Sendable, Equatable {
    public var version: String
    public var notes: String?
    public var pageURL: URL?
    /// The release's `Barnata-<version>.dmg`, nil when the release has none
    public var downloadURL: URL?
    /// Lowercase hex sha256 of the DMG, from the asset's `digest`
    public var sha256: String?

    public init(
        version: String,
        notes: String? = nil,
        pageURL: URL? = nil,
        downloadURL: URL? = nil,
        sha256: String? = nil
    ) {
        self.version = version
        self.notes = notes
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.sha256 = sha256
    }
}

/// Asks the GitHub releases API whether a version above the running one has been published
@MainActor
public final class UpdateChecker {
    public static let interval: TimeInterval = 24 * 60 * 60
    public static let timeout: TimeInterval = 15
    public static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/jacksluong/barnata/releases/latest")!

    /// Debug builds read a local feed from the `updateFeedURL` default when it is set
    public static var feedURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "updateFeedURL"),
           let url = URL(string: override) {
            return url
        }
        #endif
        return latestReleaseURL
    }

    /// Called when the answer changes, including back to nil
    public var onChange: ((AvailableUpdate?) -> Void)?

    public private(set) var available: AvailableUpdate?

    private let currentVersion: String
    private let session: URLSession
    private var timer: Timer?
    private var isChecking = false
    private var waiting: [(AvailableUpdate?) -> Void] = []

    public init(currentVersion: String, session: URLSession = .shared) {
        self.currentVersion = currentVersion
        self.session = session
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: UpdateChecker.interval, repeats: true) { _ in
            MainActor.assumeIsolated { self.check() }
        }
        check()
    }

    /// `completion` runs once this check finishes, including when it finds nothing
    public func check(completion: ((AvailableUpdate?) -> Void)? = nil) {
        if let completion { waiting.append(completion) }
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: UpdateChecker.feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = UpdateChecker.timeout

        let version = currentVersion
        session.dataTask(with: request) { [weak self] data, _, error in
            if let error {
                log.info("update check failed: \(error.localizedDescription, privacy: .public)")
            }
            let found = data.flatMap { UpdateChecker.update(in: $0, above: version) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isChecking = false
                    // A check that never reached the API keeps whatever the last good one found
                    if data != nil { self.apply(found) }
                    self.finishWaiting()
                }
            }
        }.resume()
    }

    private func finishWaiting() {
        let completions = waiting
        waiting = []
        for completion in completions { completion(available) }
    }

    private func apply(_ update: AvailableUpdate?) {
        guard update != available else { return }
        available = update
        onChange?(update)
    }

    /// The latest release, when its tag sits above `version`
    nonisolated static func update(in data: Data, above version: String) -> AvailableUpdate? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(Release.self, from: data) else { return nil }
        guard release.draft != true, release.prerelease != true else { return nil }

        let tag = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard !tag.isEmpty, compareVersions(tag, version) == .orderedDescending else { return nil }

        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let asset = release.assets?.first { $0.name == "Barnata-\(tag).dmg" }
        return AvailableUpdate(
            version: tag,
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            pageURL: release.htmlUrl.flatMap { URL(string: $0) },
            downloadURL: asset?.browserDownloadUrl.flatMap { URL(string: $0) },
            sha256: asset?.digest.flatMap(sha256Hex(fromDigest:))
        )
    }

    /// `sha256:<hex>` to lowercase hex, nil for any other algorithm or a malformed value
    nonisolated static func sha256Hex(fromDigest digest: String) -> String? {
        let prefix = "sha256:"
        guard digest.lowercased().hasPrefix(prefix) else { return nil }
        let hex = digest.dropFirst(prefix.count).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }

    private struct Release: Decodable {
        var tagName: String
        var body: String?
        var htmlUrl: String?
        var draft: Bool?
        var prerelease: Bool?
        var assets: [Asset]?
    }

    private struct Asset: Decodable {
        var name: String
        var browserDownloadUrl: String?
        var digest: String?
    }
}
