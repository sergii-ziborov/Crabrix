import SwiftUI
import XCTest
@testable import Crabrix

final class TermMatchConnectionTests: XCTestCase {
    func testNarrowGutterDoesNotBendBackOverEitherCard() {
        assertContained(start: CGPoint(x: 168, y: 100), end: CGPoint(x: 224, y: 420))
        assertContained(start: CGPoint(x: 168, y: 420), end: CGPoint(x: 224, y: 100))
        assertContained(start: CGPoint(x: 168, y: 100), end: CGPoint(x: 224, y: 100))
    }

    func testWideAndReversedLayoutsStayBetweenTheirDots() {
        assertContained(start: CGPoint(x: 250, y: 80), end: CGPoint(x: 550, y: 310))
        assertContained(start: CGPoint(x: 224, y: 420), end: CGPoint(x: 168, y: 100))
    }

    private func assertContained(start: CGPoint, end: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        let shape = TermMatchConnection(start: start, end: end)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 820, height: 900)).cgPath
        let bounds = path.boundingBoxOfPath
        XCTAssertEqual(bounds.minX, min(start.x, end.x), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(bounds.maxX, max(start.x, end.x), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(bounds.minY, min(start.y, end.y), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(bounds.maxY, max(start.y, end.y), accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(path.currentPoint, end, file: file, line: line)
    }
}
