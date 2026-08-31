import Testing
@testable import Crabrix

struct LessonNavigationFooterVisibilityTests {
    @Test func footerStaysHiddenWhileUnreadContentRemains() {
        #expect(
            !LessonNavigationFooterVisibility.shouldShow(
                contentHeight: 1_200,
                visibleMaxY: 700,
                containerHeight: 700
            )
        )
    }

    @Test func footerAppearsOnlyNearTheBottom() {
        #expect(
            LessonNavigationFooterVisibility.shouldShow(
                contentHeight: 1_200,
                visibleMaxY: 1_180,
                containerHeight: 700
            )
        )
        #expect(
            !LessonNavigationFooterVisibility.shouldShow(
                contentHeight: 1_200,
                visibleMaxY: 1_160,
                containerHeight: 700
            )
        )
    }

    @Test func footerIsImmediatelyAvailableWhenThePageFits() {
        #expect(
            LessonNavigationFooterVisibility.shouldShow(
                contentHeight: 560,
                visibleMaxY: 640,
                containerHeight: 640
            )
        )
    }

    @Test func footerDoesNotFlashBeforeScrollGeometryExists() {
        #expect(
            !LessonNavigationFooterVisibility.shouldShow(
                contentHeight: 0,
                visibleMaxY: 0,
                containerHeight: 0
            )
        )
    }
}
