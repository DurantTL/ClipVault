import XCTest

@testable import SlateBox

final class GitHubUpdateCheckServiceTests: XCTestCase {
  func testNormalizeVersionStripsVPrefix() {
    XCTAssertEqual(GitHubReleaseDTO.normalizeVersion("v1.2.3"), "1.2.3")
    XCTAssertEqual(GitHubReleaseDTO.normalizeVersion("1.0.0"), "1.0.0")
  }

  func testCompareVersionsOrdersSemverSegments() {
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("1.0.1", "1.0.0"), .orderedDescending)
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("1.0.0", "1.0.1"), .orderedAscending)
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("1.0", "1.0.0"), .orderedSame)
    XCTAssertEqual(GitHubUpdateCheckService.compareVersions("2.0.0", "1.9.9"), .orderedDescending)
  }

  func testDecodeReleasePrefersDMGAssetURL() throws {
    let json = """
    {
      "tag_name": "v1.2.0",
      "name": "SlateBox 1.2.0",
      "html_url": "https://github.com/DurantTL/ClipVault/releases/tag/v1.2.0",
      "draft": false,
      "prerelease": false,
      "assets": [
        {
          "name": "SlateBox-1.2.0.dmg",
          "browser_download_url": "https://github.com/DurantTL/ClipVault/releases/download/v1.2.0/SlateBox-1.2.0.dmg"
        }
      ]
    }
    """.data(using: .utf8)!

    let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: json)
    XCTAssertEqual(release.normalizedVersion, "1.2.0")
    XCTAssertEqual(
      release.preferredOpenURL?.absoluteString,
      "https://github.com/DurantTL/ClipVault/releases/download/v1.2.0/SlateBox-1.2.0.dmg"
    )
  }
}
