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

	func stopSpeakingImmediately() -> Bool {
		stopCount += 1
		defer { isSpeaking = false }
		return isSpeaking
	}

	func completeCurrentUtterance() {
		isSpeaking = false
		delegate?.speechSynthesizerEngineDidCompleteUtterance()
	}

	func simulateActiveUtterance() {
		isSpeaking = true
	}

	/// The engine finishing without ever telling its delegate, which is what a
	/// dropped completion callback looks like from the queue's side.
	func finishWithoutNotifying() {
		isSpeaking = false
	}
}

@MainActor
private final class SpeechSynthesizerEngineDelegateSpy: NSObject, SpeechSynthesizerEngineDelegate {
	func speechSynthesizerEngineDidCompleteUtterance() {}
}

@MainActor
@Suite("Speech synthesizer queue")
struct SpeechSynthesizerTests {
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

	@Test("Mute stops active notification speech and drops only notification backlog")
	func muteKeepsExplicitSpeech() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)
		synthesizer.speak(notification("active notification"))
		synthesizer.speak(notification("pending notification"))
		synthesizer.speak(text: "explicit speech")
		synthesizer.setNotificationsMuted(true)
		synthesizer.speak(notification("muted notification"))
		#expect(engine.stopCount == 1)
		#expect(synthesizer.pendingItemCount == 1)
		// Stop completes asynchronously. Do not start a new utterance before
		// that completion can retire the previous one.
		synthesizer.speak(text: "another explicit request")
		#expect(engine.spokenTexts == ["active notification"])
		engine.completeCurrentUtterance()
		#expect(engine.spokenTexts == ["active notification", "explicit speech"])
		engine.completeCurrentUtterance()
		#expect(engine.spokenTexts.last == "another explicit request")
	}

	@Test("Mute leaves an explicit utterance running and unmute does not replay stale notifications")
	func muteDoesNotStopExplicitUtterance() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)
		synthesizer.speak(text: "explicit")
		synthesizer.speak(notification("stale"))
		synthesizer.setNotificationsMuted(true)
		synthesizer.setNotificationsMuted(false)
		synthesizer.speak(notification("fresh"))
		#expect(engine.stopCount == 0)
		engine.completeCurrentUtterance()
		#expect(engine.spokenTexts == ["explicit", "fresh"])
	}

	@Test("Notification backlog retains a bounded number of recent requests")
	func backlogIsBounded() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)
		synthesizer.speak(text: "active")
		for index in 0 ..< 100 {
			synthesizer.speak(notification("notification \(index)"))
		}
		#expect(synthesizer.pendingItemCount == UInt(SpeechSynthesizer.maximumPendingNotifications))
		engine.completeCurrentUtterance()
		#expect(engine.spokenTexts.last == "notification 36")
	}

	@Test("Oversized notification speech is refused without consuming queue capacity")
	func oversizedNotification() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)
		synthesizer.speak(notification(String(repeating: "x", count: SpeechSynthesizer.maximumNotificationBytes + 1)))
		#expect(engine.spokenTexts.isEmpty)
		#expect(synthesizer.pendingItemCount == 0)
	}

	@Test("A completion the engine never reports does not wedge the queue")
	func missedCompletionDoesNotWedgeTheQueue() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "first")
		engine.finishWithoutNotifying()
		synthesizer.speak(text: "second")

		#expect(engine.spokenTexts == ["first", "second"])
		#expect(synthesizer.pendingItemCount == 0)
	}

	@Test("Skipping forward moves on even when the engine has already gone quiet")
	func skippingForwardAdvancesAnEngineThatWentQuiet() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "first")
		synthesizer.speak(text: "second")
		engine.finishWithoutNotifying()
		synthesizer.stopSpeakingAndMoveForward()

		#expect(engine.stopCount == 0)
		#expect(engine.spokenTexts == ["first", "second"])
		#expect(synthesizer.pendingItemCount == 0)
	}

	@Test("Skipping a live utterance cancels it and lets its callback move the queue on")
	func skippingALiveUtteranceWaitsForItsCancellation() {
		let engine = SpeechSynthesizerEngineSpy()
		let synthesizer = SpeechSynthesizer(engine: engine)

		synthesizer.speak(text: "first")
		synthesizer.speak(text: "second")
		synthesizer.stopSpeakingAndMoveForward()

		#expect(engine.stopCount == 1)
		#expect(engine.spokenTexts == ["first"])

		engine.completeCurrentUtterance()

		#expect(engine.spokenTexts == ["first", "second"])
	}

	private func notification(_ text: String) -> SpeechItem {
		var notification = SpokenNotification(
			notificationType: .connect,
			lineType: .notice,
			target: nil,
			nickname: nil,
			text: text
		)
		notification.spokenText = text
		return .notification(notification)
	}
}
