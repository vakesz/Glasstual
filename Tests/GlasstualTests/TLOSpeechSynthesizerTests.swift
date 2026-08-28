/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
private final class SpeechSynthesizerEngineSpy: NSObject, SpeechSynthesizerEngine {
	weak var delegate: SpeechSynthesizerEngineDelegate?
	private(set) var isSpeaking = false
	private(set) var stopCount = 0
	private(set) var spokenTexts: [String] = []

	func speakText(_ text: String) {
		spokenTexts.append(text)
		isSpeaking = true
	}

	func stopSpeakingImmediately() {
		stopCount += 1
		isSpeaking = false
	}

	func completeCurrentUtterance() {
		isSpeaking = false
		delegate?.speechSynthesizerEngineDidCompleteUtterance()
	}

	func simulateActiveUtterance() {
		isSpeaking = true
	}
}

@MainActor
private final class SpeechSynthesizerEngineDelegateSpy: NSObject, SpeechSynthesizerEngineDelegate {
	func speechSynthesizerEngineDidCompleteUtterance() {}
}

@MainActor
final class TLOSpeechSynthesizerTests: XCTestCase {
	func testAVSpeechEngineKeepsItsDelegateWeak() {
		let engine = AVSpeechSynthesizerEngine()
		weak var weakDelegate: SpeechSynthesizerEngineDelegateSpy?

		autoreleasepool {
			let delegate = SpeechSynthesizerEngineDelegateSpy()
			weakDelegate = delegate
			engine.delegate = delegate

			XCTAssertTrue(engine.delegate === delegate)
		}

		XCTAssertNil(weakDelegate)
		XCTAssertNil(engine.delegate)
	}

	func testQueuedTextStartsInOrderAsUtterancesComplete() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "first")
		synthesizer.speak(text: "second")

		XCTAssertEqual(engine.spokenTexts, ["first"])
		XCTAssertEqual(synthesizer.pendingItemCount, 1)

		engine.completeCurrentUtterance()

		XCTAssertEqual(engine.spokenTexts, ["first", "second"])
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
	}

	func testStoppingRejectsNewItemsAndStopsCurrentUtterance() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "active")
		synthesizer.isStopped = true
		synthesizer.speak(text: "ignored")

		XCTAssertEqual(engine.stopCount, 1)
		XCTAssertEqual(engine.spokenTexts, ["active"])
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
	}

	func testClearQueueLeavesCurrentUtteranceAlone() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "active")
		synthesizer.speak(text: "queued")
		synthesizer.clearQueue()

		XCTAssertTrue(engine.isSpeaking)
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
		XCTAssertEqual(engine.spokenTexts, ["active"])
	}

	func testClearQueueForClientRemovesOnlyMatchingNotifications() {
		let engine = SpeechSynthesizerEngineSpy()
		engine.simulateActiveUtterance()

		let synthesizer = SpeechSynthesizer(engine: engine)
		let firstClient = GLTTestClient()
		let secondClient = GLTTestClient()
		var firstNotification = SpokenNotification(
			notificationType: .connect,
			lineType: .notice,
			target: firstClient,
			nickname: "first",
			text: "one"
		)
		var secondNotification = SpokenNotification(
			notificationType: .connect,
			lineType: .notice,
			target: secondClient,
			nickname: "second",
			text: "two"
		)
		/* The producer formats a notification before queueing it. */
		firstNotification.spokenText = "one"
		secondNotification.spokenText = "two"

		synthesizer.speak(.notification(firstNotification))
		synthesizer.speak(.notification(secondNotification))
		synthesizer.speak(text: "plain text")
		synthesizer.clearQueue(for: firstClient)

		XCTAssertEqual(synthesizer.pendingItemCount, 2)

		engine.completeCurrentUtterance()

		XCTAssertEqual(synthesizer.pendingItemCount, 1)
	}

	func testNotificationWithoutSpokenTextDoesNotBlockFollowingText() {
		let engine = SpeechSynthesizerEngineSpy()
		engine.simulateActiveUtterance()

		let synthesizer = SpeechSynthesizer(engine: engine)
		let unformatted = SpokenNotification(
			notificationType: .connect,
			lineType: .notice,
			target: GLTTestClient(),
			nickname: "nobody",
			text: "unformatted"
		)

		synthesizer.speak(.notification(unformatted))
		synthesizer.speak(text: "valid")

		engine.completeCurrentUtterance()

		XCTAssertEqual(engine.spokenTexts, ["valid"])
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
	}
}
