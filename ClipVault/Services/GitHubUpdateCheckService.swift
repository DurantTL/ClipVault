import AppKit
import Foundation

/// Manual "Check for Updates" against GitHub Releases (no Sparkle).
/// Local-only UX — no telemetry. Does not download or install DMGs.
enum UpdateCheckResult: Equatable {
  case upToDate(current: String)
  case updateAvailable(current: String, latest: String, releaseName: String, pageURL: URL)
  case noReleases
  case offline
  case rateLimited
  case failed(message: String)
}

struct GitHubReleaseDTO: Decodable, Equatable {
  let tagName: String
  let name: String?
  let htmlURL: String
  let draft: Bool
  let prerelease: Bool
  let assets: [Asset]

  struct Asset: Decodable, Equatable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
      case name
      case browserDownloadURL = "browser_download_url"
    }
  }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case name
    case htmlURL = "html_url"
    case draft
    case prerelease
    case assets
  }

  var normalizedVersion: String {
    Self.normalizeVersion(tagName)
  }

  var preferredOpenURL: URL? {
    if let dmg = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
      let url = URL(string: dmg.browserDownloadURL)
    {
      return url
    }
    return URL(string: htmlURL)
  }

  static func normalizeVersion(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.lowercased().hasPrefix("v") {
      s.removeFirst()
    }
    return s
  }
}

struct GitHubUpdateCheckService {
  var owner = "DurantTL"
  var repo = "ClipVault"
  var session: URLSession = .shared
  var currentVersionProvider: () -> String = {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  func checkForUpdates() async -> UpdateCheckResult {
    let current = GitHubReleaseDTO.normalizeVersion(currentVersionProvider())
    guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
      return .failed(message: "Invalid updates URL.")
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("ClipVault-UpdateCheck", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 20

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        return .failed(message: "Unexpected response from GitHub.")
      }

      switch http.statusCode {
      case 200:
        break
      case 404:
        return .noReleases
      case 403, 429:
        return .rateLimited
      default:
        return .failed(message: "GitHub returned status \(http.statusCode).")
      }

      let decoder = JSONDecoder()
      let release = try decoder.decode(GitHubReleaseDTO.self, from: data)
      if release.draft {
        return .noReleases
      }

      let latest = release.normalizedVersion
      if Self.compareVersions(latest, current) == .orderedDescending {
        guard let pageURL = release.preferredOpenURL else {
          return .failed(message: "Release has no usable URL.")
        }
        let title = (release.name?.isEmpty == false) ? (release.name ?? latest) : latest
        return .updateAvailable(current: current, latest: latest, releaseName: title, pageURL: pageURL)
      }
      return .upToDate(current: current)
    } catch let error as URLError {
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
        return .offline
      default:
        return .failed(message: error.localizedDescription)
      }
    } catch {
      return .failed(message: error.localizedDescription)
    }
  }

  /// Compare dotted numeric versions (`1.2.3`). Non-numeric segments compare as 0.
  static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(left.count, right.count)
    for i in 0..<count {
      let a = i < left.count ? left[i] : 0
      let b = i < right.count ? right[i] : 0
      if a != b { return a < b ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
  }

  @MainActor
  func presentCheck() async {
    let result = await checkForUpdates()
    let alert = NSAlert()
    alert.alertStyle = .informational

    switch result {
    case .upToDate(let current):
      alert.messageText = "You’re up to date"
      alert.informativeText = "\(AppBrand.appName) \(current) is the latest release."
      alert.addButton(withTitle: "OK")
      alert.runModal()

    case .updateAvailable(let current, let latest, let releaseName, let pageURL):
      alert.messageText = "Update available"
      alert.informativeText = "\(AppBrand.appName) \(latest) is available (you have \(current)).\n\n\(releaseName)"
      alert.addButton(withTitle: "View Release")
      alert.addButton(withTitle: "Later")
      if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(pageURL)
      }

    case .noReleases:
      alert.messageText = "No releases found"
      alert.informativeText = "GitHub has no published releases for this app yet."
      alert.addButton(withTitle: "OK")
      alert.runModal()

    case .offline:
      alert.alertStyle = .warning
      alert.messageText = "Can’t check for updates"
      alert.informativeText = "You’re offline or GitHub couldn’t be reached. Try again when you have a network connection."
      alert.addButton(withTitle: "OK")
      alert.runModal()

    case .rateLimited:
      alert.alertStyle = .warning
      alert.messageText = "GitHub is busy"
      alert.informativeText = "Update checks are rate-limited right now. Try again in a few minutes."
      alert.addButton(withTitle: "OK")
      alert.runModal()

    case .failed(let message):
      alert.alertStyle = .warning
      alert.messageText = "Update check failed"
      alert.informativeText = message
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }
}
