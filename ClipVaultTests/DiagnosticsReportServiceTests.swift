import XCTest

@testable import SlateBox

final class DiagnosticsReportServiceTests: XCTestCase {
  func testReportContainsAppSystemSettingsAndRecentProjectSections() throws {
    let suiteName = "clipvault-diagnostics-test-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("strong", forKey: "verificationMode")
    defaults.set(["/Volumes/Missing/Project/.clipvault-project.json"], forKey: "recentProjects")

    let report = DiagnosticsReportService().report(defaults: defaults)

    XCTAssertTrue(report.contains("\(AppBrand.appName) Diagnostics Report"))
    XCTAssertTrue(report.contains("[App]"))
    XCTAssertTrue(report.contains("[System]"))
    XCTAssertTrue(report.contains("Physical memory:"))
    XCTAssertTrue(report.contains("Verification mode: strong"))
    XCTAssertTrue(report.contains("[Recent Projects] (1)"))
    XCTAssertTrue(report.contains("/Volumes/Missing/Project/.clipvault-project.json — not mounted"))
  }

  func testReportUsesDefaultsWhenNothingIsSet() throws {
    let suiteName = "clipvault-diagnostics-empty-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let report = DiagnosticsReportService().report(defaults: defaults)

    XCTAssertTrue(report.contains("Verification mode: fast"))
    XCTAssertTrue(report.contains("Performance mode: Automatic"))
    XCTAssertTrue(report.contains("[Recent Projects] (0)"))
    XCTAssertTrue(report.contains("none"))
  }
}
