import XCTest

/// The Learn library without "⋯" buttons: a course card swiped from right to
/// left shows its actions, a tap on the open card closes it instead of opening
/// the course, and the loading state reads as one centred line.
@MainActor
final class LearnLibrarySwipeUITests: XCTestCase {
    private let app = XCUIApplication()

    func testCourseCardSwipeRevealsActionsAndTapCloses() throws {
        continueAfterFailure = true
        app.launchArguments = ["-crabrix.appearance", "light", "-CrabrixTab", "learn"]
        app.launch()
        capture("01-loading")

        let course = app.otherElements["learn-course-basics"]
        XCTAssertTrue(course.waitForExistence(timeout: 60), "Rust Basics is bundled")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.buttons["Manage download for Rust Basics"].exists, "the ⋯ menu is gone")
        XCTAssertFalse(app.buttons["Code Examples options"].exists, "the ⋯ menu is gone")
        capture("02-library")

        // A vertical swipe that starts on a card scrolls the library: the
        // card swipe only takes horizontal movement.
        let top = course.frame.minY
        course.swipeUp()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertLessThan(course.frame.minY, top - 150, "the library scrolls from a card")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(course.frame.minY, top, accuracy: 4, "back at the top")

        course.swipeLeft()
        Thread.sleep(forTimeInterval: 0.8)
        capture("03-swiped")

        // A tap on the open card closes it; the library stays.
        app.buttons["learn-open-course-basics"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(course.exists && app.navigationBars["Learn"].exists, "tap closes the card, no navigation")
        capture("04-closed")

        // Closed again, a tap opens the course as before.
        app.buttons["learn-open-course-basics"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.navigationBars["Learn"].exists, "a closed card opens its course")
    }

    private func capture(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["CRABRIX_SWIPE_SCREENSHOTS"], !directory.isEmpty else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("learn-library-\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
