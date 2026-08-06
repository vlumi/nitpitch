import XCTest

@testable import NitpitchKit

/// The fan-out is the whole reason this type exists — a screen must be able to
/// listen without owning the microphone, and several must be able to listen at
/// once. These cover that without touching AVFoundation: an `AudioInput` is
/// constructed but never started, and windows are pushed through its
/// `onWindow` hook the way the real tap would.
@MainActor
final class AudioSessionControllerTests: XCTestCase {
    /// Feeds a window in as the audio tap would, bypassing the engine.
    private func deliver(_ window: [Float], through input: AudioInput) {
        input.onWindow?(window)
    }

    func testDeliversWindowsToASubscriber() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        var received: [[Float]] = []
        let subscription = controller.subscribe { received.append($0) }

        deliver([1, 2, 3], through: input)

        XCTAssertEqual(received, [[1, 2, 3]])
        subscription.cancel()
    }

    /// The point of the type: `AudioInput.onWindow` holds one closure, so
    /// without fan-out a second listener would silently displace the first.
    func testEverySubscriberSeesEveryWindow() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        var first: [[Float]] = []
        var second: [[Float]] = []
        let a = controller.subscribe { first.append($0) }
        let b = controller.subscribe { second.append($0) }

        deliver([1], through: input)
        deliver([2], through: input)

        XCTAssertEqual(first, [[1], [2]])
        XCTAssertEqual(second, [[1], [2]])
        a.cancel()
        b.cancel()
    }

    func testCancellingStopsDelivery() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        var received: [[Float]] = []
        let subscription = controller.subscribe { received.append($0) }

        deliver([1], through: input)
        subscription.cancel()
        deliver([2], through: input)

        XCTAssertEqual(received, [[1]], "no windows after cancel")
    }

    /// Releasing the handle has to be enough — a screen going away shouldn't
    /// have to remember to clean up, and forgetting would leak a live closure.
    func testReleasingTheSubscriptionStopsDelivery() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        var received: [[Float]] = []
        do {
            let subscription = controller.subscribe { received.append($0) }
            deliver([1], through: input)
            _ = subscription
        }
        deliver([2], through: input)

        XCTAssertEqual(received, [[1]], "no windows after the handle went away")
    }

    /// Cancelling one must not disturb the others — the grid will have several
    /// live at once, appearing and disappearing as cells scroll.
    func testCancellingOneLeavesTheRest() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        var kept: [[Float]] = []
        let dropped = controller.subscribe { _ in }
        let survivor = controller.subscribe { kept.append($0) }

        dropped.cancel()
        deliver([7], through: input)

        XCTAssertEqual(kept, [[7]])
        survivor.cancel()
    }

    func testStartsIdleAndExposesTheDetectorSampleRate() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        XCTAssertEqual(controller.status, .idle)
        XCTAssertEqual(controller.sampleRate, input.sampleRate)
    }

    /// Suspending is for backgrounding, so subscriptions have to survive it —
    /// otherwise returning to the foreground would show a dead display.
    func testSuspendKeepsSubscriptionsAlive() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        var received: [[Float]] = []
        let subscription = controller.subscribe { received.append($0) }

        controller.suspend()
        XCTAssertEqual(controller.status, .idle)
        deliver([5], through: input)

        XCTAssertEqual(received, [[5]], "still subscribed after suspend")
        subscription.cancel()
    }

    /// Activity keeps the screen awake; the throttle tolerates the ~21 Hz
    /// poke rate without churning. (The 90 s release deadline is real time
    /// and stays field-verified.)
    func testTuningActivityKeepsTheScreenAwake() {
        let controller = AudioSessionController(input: AudioInput())
        XCTAssertFalse(controller.isKeepingScreenAwake)
        controller.pokeScreenAwake()
        XCTAssertTrue(controller.isKeepingScreenAwake)
        controller.pokeScreenAwake()
        XCTAssertTrue(controller.isKeepingScreenAwake, "repeat pokes are harmless")
    }
}
