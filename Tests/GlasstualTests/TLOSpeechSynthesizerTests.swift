/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import XCTest

private final class SpeechSynthesizerEngineSpy: NSObject, TLOSpeechSynthesizerEngine {
	weak var delegate: TLOSpeechSynthesizerEngineDelegate?
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

final class TLOSpeechSynthesizerTests: XCTestCase {
	func testQueuedTextStartsInOrderAsUtterancesComplete() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = TLOSpeechSynthesizer(engine: engine)

		synthesizer.speak("first")
		synthesizer.speak("second")

		XCTAssertEqual(engine.spokenTexts, ["first"])
		XCTAssertEqual(synthesizer.pendingItemCount, 1)

		engine.completeCurrentUtterance()

		XCTAssertEqual(engine.spokenTexts, ["first", "second"])
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
	}

	func testStoppingRejectsNewItemsAndStopsCurrentUtterance() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = TLOSpeechSynthesizer(engine: engine)

		synthesizer.speak("active")
		synthesizer.isStopped = true
		synthesizer.speak("ignored")

		XCTAssertEqual(engine.stopCount, 1)
		XCTAssertEqual(engine.spokenTexts, ["active"])
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
	}

	func testClearQueueLeavesCurrentUtteranceAlone() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = TLOSpeechSynthesizer(engine: engine)

		synthesizer.speak("active")
		synthesizer.speak("queued")
		synthesizer.clearQueue()

		XCTAssertTrue(engine.isSpeaking)
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
		XCTAssertEqual(engine.spokenTexts, ["active"])
	}

	func testClearQueueForClientRemovesOnlyMatchingNotifications() {
		let engine = SpeechSynthesizerEngineSpy()
		engine.simulateActiveUtterance()

		let synthesizer = TLOSpeechSynthesizer(engine: engine)
		let firstClient = GLTTestClient()
		let secondClient = GLTTestClient()
		let firstNotification = TLOSpokenNotification(
			notification: .connect,
			lineType: .notice,
			target: firstClient,
			nickname: "first",
			text: "one"
		)
		let secondNotification = TLOSpokenNotification(
			notification: .connect,
			lineType: .notice,
			target: secondClient,
			nickname: "second",
			text: "two"
		)

		synthesizer.speak(firstNotification)
		synthesizer.speak(secondNotification)
		synthesizer.speak("plain text")
		synthesizer.clearQueue(for: firstClient)

		XCTAssertEqual(synthesizer.pendingItemCount, 2)

		engine.completeCurrentUtterance()

		XCTAssertEqual(synthesizer.pendingItemCount, 1)
	}

	func testUnsupportedQueueItemDoesNotBlockFollowingText() {
		let engine = SpeechSynthesizerEngineSpy()
		engine.simulateActiveUtterance()

		let synthesizer = TLOSpeechSynthesizer(engine: engine)

		synthesizer.speak(42)
		synthesizer.speak("valid")

		engine.completeCurrentUtterance()

		XCTAssertEqual(engine.spokenTexts, ["valid"])
		XCTAssertEqual(synthesizer.pendingItemCount, 0)
	}
}
