import Foundation
import XCTest
@testable import GoVietShellCore

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }
}

final class InjectionSchedulerTests: XCTestCase {
    func testDeferredPhysicalEventRunsAfterSlowReplacement() {
        let queue = DispatchQueue(label: "InjectionSchedulerTests.order")
        let scheduler = InjectionScheduler(queue: queue)
        let firstStarted = expectation(description: "slow replacement started")
        let allFinished = expectation(description: "all operations finished")
        allFinished.expectedFulfillmentCount = 2

        let releaseFirst = DispatchSemaphore(value: 0)
        let order = LockedBox<[String]>([])

        XCTAssertTrue(scheduler.schedule(force: true) {
            firstStarted.fulfill()
            releaseFirst.wait()
            order.withValue { $0.append("replacement") }
            allFinished.fulfill()
        })
        wait(for: [firstStarted], timeout: 1)

        XCTAssertTrue(scheduler.hasPending)
        XCTAssertTrue(scheduler.schedule(force: false) {
            order.withValue { $0.append("physical") }
            allFinished.fulfill()
        })
        XCTAssertEqual(scheduler.pendingCount, 2)

        releaseFirst.signal()
        wait(for: [allFinished], timeout: 1)
        queue.sync {}

        XCTAssertEqual(order.withValue { $0 }, ["replacement", "physical"])
        XCTAssertFalse(scheduler.hasPending)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testFastOperationRunsInlineWhenQueueIsIdle() {
        let scheduler = InjectionScheduler(
            queue: DispatchQueue(label: "InjectionSchedulerTests.inline")
        )
        let ran = LockedBox(false)
        XCTAssertFalse(scheduler.schedule(force: false) { ran.withValue { $0 = true } })
        XCTAssertFalse(ran.withValue { $0 })
    }
}
