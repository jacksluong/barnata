import Foundation

/// A published release newer than the running app
public struct AvailableUpdate: Sendable, Equatable {
    public var version: String
    public var notes: String?
    public var pageURL: URL?

    public init(version: String, notes: String? = nil, pageURL: URL? = nil) {
        self.version = version
        self.notes = notes
        self.pageURL = pageURL
    }
}

/// Asks the GitHub releases API whether a version above the running one has been published
@MainActor
public final class UpdateChecker {
    public static let interval: TimeInterval = 24 * 60 * 60
    public static let timeout: TimeInterval = 15
    public static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/jacksluong/barnata/releases/latest")!

    /// Called when the answer changes, including back to nil
    public var onChange: ((AvailableUpdate?) -> Void)?

    public private(set) var available: AvailableUpdate?

    private let currentVersion: String
    private let session: URLSession
    private var timer: Timer?
    private var isChecking = false

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

    public func stop() {
        timer?.invalidate()
        timer = nil
        apply(nil)
    }

    public func check() {
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: UpdateChecker.latestReleaseURL)
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
                    guard data != nil else { return }
                    self.apply(found)
                }
            }
        }.resume()
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
        return AvailableUpdate(
            version: tag,
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            pageURL: release.htmlUrl.flatMap { URL(string: $0) }
        )
    }

    private struct Release: Decodable {
        var tagName: String
        var body: String?
        var htmlUrl: String?
        var draft: Bool?
        var prerelease: Bool?
    }
}
