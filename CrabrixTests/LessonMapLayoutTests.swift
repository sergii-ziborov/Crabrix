import XCTest
@testable import Crabrix

final class LessonMapLayoutTests: XCTestCase {
    func testLessonLabelsStayInsideCompactAndRegularWidths() {
        for width: CGFloat in [280, 320, 339, 534, 760] {
            for index in 0..<16 {
                let labelWidth = LessonMapLayout.labelWidth(for: width)
                let nodeX = LessonMapLayout.nodeCenterX(width: width, index: index)
                let labelX = LessonMapLayout.labelCenterX(
                    width: width,
                    nodeX: nodeX,
                    labelWidth: labelWidth,
                    labelToRight: LessonMapLayout.labelToRight(at: index)
                )

                XCTAssertGreaterThanOrEqual(
                    labelX - labelWidth / 2,
                    LessonMapLayout.edgeInset,
                    "Left edge escaped at width \(width), node \(index)"
                )
                XCTAssertLessThanOrEqual(
                    labelX + labelWidth / 2,
                    width - LessonMapLayout.edgeInset,
                    "Right edge escaped at width \(width), node \(index)"
                )
            }
        }
    }

    func testNodesStayInsideTheirContainer() {
        for width: CGFloat in [280, 320, 339, 534, 760] {
            for index in 0..<16 {
                let nodeX = LessonMapLayout.nodeCenterX(width: width, index: index)
                let radius = LessonMapLayout.nodeDiameter / 2
                XCTAssertGreaterThanOrEqual(
                    nodeX - radius,
                    LessonMapLayout.edgeInset
                )
                XCTAssertLessThanOrEqual(
                    nodeX + radius,
                    width - LessonMapLayout.edgeInset
                )
            }
        }
    }
}
