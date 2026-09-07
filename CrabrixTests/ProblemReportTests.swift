import UIKit
import XCTest
@testable import Crabrix

/// A bug report is an email the reader writes and sends. These tests pin down
/// what goes into it — and, just as much, what never does.
final class ProblemReportTests: XCTestCase {
    private let environment = ProblemReportEnvironment(
        appVersion: "1.0",
        appBuild: "2",
        systemVersion: "26.0",
        deviceModel: "iPhone14,4",
        rustcVersion: "1.96.0-dev",
        toolchainArtifact: "artifacts-test-7",
        target: "wasm32-wasip1",
        toolchainIsReady: true
    )

    private func filledReport() -> ProblemReport {
        var report = ProblemReport()
        report.area = .packages
        report.whatHappened = "Adding smallvec 1.13 fails to resolve while offline."
        report.whatIExpected = "The pinned copy should be used."
        return report
    }

    func testAnEmptyReportCannotBeSent() {
        var report = ProblemReport()
        XCTAssertFalse(report.isReady, "an empty report is not a report")

        report.whatHappened = "   \n  "
        XCTAssertFalse(report.isReady, "whitespace is not a description")

        report.whatHappened = "It crashed."
        XCTAssertTrue(report.isReady)
    }

    func testTheReportCarriesWhatWasWrittenAndTheArea() {
        let body = filledReport().body(environment)

        XCTAssertTrue(body.contains("Adding smallvec 1.13 fails to resolve while offline."))
        XCTAssertTrue(body.contains("The pinned copy should be used."))
        XCTAssertEqual(filledReport().subject, "Crabrix — Packages and crates.io")
    }

    func testAnEmptyExpectationLeavesNoEmptyHeading() {
        var report = filledReport()
        report.whatIExpected = "  "
        XCTAssertFalse(
            report.body(environment).contains("What I expected"),
            "an unanswered optional question should not appear at all"
        )
    }

    func testDeviceDetailsAreAttachedOnlyWhenAsked() {
        var report = filledReport()
        XCTAssertTrue(report.body(environment).contains("Crabrix 1.0 (build 2)"))
        XCTAssertTrue(report.body(environment).contains("iOS 26.0 on iPhone14,4"))
        XCTAssertTrue(report.body(environment).contains("artifacts-test-7"))

        report.includesEnvironment = false
        let body = report.body(environment)
        XCTAssertFalse(body.contains("iPhone14,4"), "the toggle has to actually remove the details")
        XCTAssertFalse(body.contains("artifacts-test-7"))
        XCTAssertTrue(body.contains("Adding smallvec"), "what was written must survive either way")
    }

    /// The device name is usually a person's name. It is not diagnostics.
    func testTheDeviceNameIsNeverAttached() {
        let attached = environment.lines.joined(separator: "\n")
        XCTAssertFalse(attached.lowercased().contains("iphone14,4's"))
        XCTAssertFalse(
            attached.contains(UIDevice.current.name),
            "the report must not carry the name the owner gave their device"
        )
        XCTAssertEqual(environment.lines.count, 4, "only the four facts triage needs")
    }

    func testTheModelIdentifierIsTheHardwareString() {
        let model = ProblemReportEnvironment.modelIdentifier
        XCTAssertFalse(model.isEmpty)
        XCTAssertFalse(model.contains(" "), "a model identifier has no spaces: \(model)")
    }

    func testTheMailDraftAddressesSupportAndCarriesTheReport() throws {
        let url = try XCTUnwrap(filledReport().mailURL(environment, to: CrabrixLinks.supportEmail))
        XCTAssertEqual(url.scheme, "mailto")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, CrabrixLinks.supportEmail)

        let items = try XCTUnwrap(components.queryItems)
        let subject = try XCTUnwrap(items.first { $0.name == "subject" }?.value)
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)

        XCTAssertEqual(subject, "Crabrix — Packages and crates.io")
        XCTAssertTrue(body.contains("Adding smallvec 1.13 fails to resolve while offline."))
        XCTAssertTrue(body.contains("iPhone14,4"))
        XCTAssertTrue(
            url.absoluteString.contains("%0A") || url.absoluteString.contains("%0D"),
            "the newlines between sections have to survive the URL"
        )
    }

    func testAPlusInTheReportSurvivesTheMailDraft() throws {
        var report = filledReport()
        report.whatHappened = "let total = a + b; panics"
        let url = try XCTUnwrap(report.mailURL(environment, to: CrabrixLinks.supportEmail))

        XCTAssertFalse(
            url.absoluteString.contains("a+%2B+b") || url.absoluteString.contains("a + b"),
            "a raw plus in a mailto query arrives as a space"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("a + b"), "the plus has to come out the other side intact")
    }

    /// The address is a person's own inbox. It belongs in a mail draft, not
    /// in a string a screenshot or a scraper can carry away.
    func testTheSupportAddressIsAWorkingAddressAndIsNotAWebsiteOne() {
        let address = CrabrixLinks.supportEmail
        XCTAssertTrue(address.contains("@"), "not an address at all")
        XCTAssertFalse(address.hasSuffix("@crabrix.com"), "the domain inbox is gone; this must not point at it")
        XCTAssertFalse(address.contains(" "), "an address with a space in it reaches nobody")
    }

    func testEveryAreaHasItsOwnPromptAndIcon() {
        let hints = Set(ProblemArea.allCases.map(\.hint))
        let icons = Set(ProblemArea.allCases.map(\.icon))
        XCTAssertEqual(hints.count, ProblemArea.allCases.count, "a shared prompt helps nobody")
        XCTAssertEqual(icons.count, ProblemArea.allCases.count)
        XCTAssertFalse(ProblemArea.allCases.contains { $0.rawValue.isEmpty })
    }
}
