/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

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
@Suite("Speech synthesizer queue")
struct TLOSpeechSynthesizerTests {
	@Test("The AV engine does not keep its delegate alive")
	func avSpeechEngineKeepsItsDelegateWeak() {
		let engine = AVSpeechSynthesizerEngine()
		weak var weakDelegate: SpeechSynthesizerEngineDelegateSpy?

		autoreleasepool {
			let delegate = SpeechSynthesizerEngineDelegateSpy()
			weakDelegate = delegate
			engine.delegate = delegate

			#expect(engine.delegate === delegate)
		}

		#expect(weakDelegate == nil)
		#expect(engine.delegate == nil)
	}

	@Test("Queued text is spoken in order as each utterance finishes")
	func queuedTextStartsInOrderAsUtterancesComplete() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "first")
		synthesizer.speak(text: "second")

		#expect(engine.spokenTexts == ["first"])
		#expect(synthesizer.pendingItemCount == 1)

		engine.completeCurrentUtterance()

		#expect(engine.spokenTexts == ["first", "second"])
		#expect(synthesizer.pendingItemCount == 0)
	}

	@Test("Stopping cuts the current utterance short and refuses new items")
	func stoppingRejectsNewItemsAndStopsCurrentUtterance() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "active")
		synthesizer.isStopped = true
		synthesizer.speak(text: "ignored")

		#expect(engine.stopCount == 1)
		#expect(engine.spokenTexts == ["active"])
		#expect(synthesizer.pendingItemCount == 0)
	}

	@Test("Clearing the queue leaves whatever is being spoken alone")
	func clearQueueLeavesCurrentUtteranceAlone() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "active")
		synthesizer.speak(text: "queued")
		synthesizer.clearQueue()

		#expect(engine.isSpeaking)
		#expect(synthesizer.pendingItemCount == 0)
		#expect(engine.spokenTexts == ["active"])
	}

	@Test("Clearing one client's notifications leaves the other client's queued")
	func clearQueueForClientRemovesOnlyMatchingNotifications() {
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

		#expect(synthesizer.pendingItemCount == 2)

		engine.completeCurrentUtterance()

		#expect(synthesizer.pendingItemCount == 1)
	}

	@Test("A notification with nothing to say does not hold up the text behind it")
	func notificationWithoutSpokenTextDoesNotBlockFollowingText() {
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

		#expect(engine.spokenTexts == ["valid"])
		#expect(synthesizer.pendingItemCount == 0)
	}
}
