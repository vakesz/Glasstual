/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/** The synthesizer drives an `AVSpeechSynthesizer` and is fed from the IRC
 notification path, both of which end up on the main actor. Isolating the whole
 type removes the recursive lock that used to be held across a synchronous
 main-queue hop while formatting a notification. */
@MainActor
public final class SpeechSynthesizer: NSObject, SpeechSynthesizerEngineDelegate {
	/** What the queue believes the engine is doing.

	 The engine's own `isSpeaking` is the authority on `.speaking`: a completion
	 callback the engine never delivers would otherwise leave an utterance
	 recorded here forever, and nothing behind it would ever be spoken. */
	private enum EngineState {
		case idle
		case speaking(SpeechItem)
		/// A stop this type asked for. The engine answers it with a cancel
		/// callback, and starting anything before that arrives races it.
		case stopping
	}

	private let engine: SpeechSynthesizerEngine
	private var pendingItems: [SpeechItem] = []
	private var stopped = false
	private var engineState = EngineState.idle
	private var notificationsMuted = false
	static let maximumPendingNotifications = 64
	static let maximumNotificationBytes = 16 * 1024

	override public convenience init() {
		self.init(engine: AVSpeechSynthesizerEngine())
	}

	public init(engine: SpeechSynthesizerEngine) {
		self.engine = engine

		super.init()

		engine.delegate = self
	}

	public var isStopped: Bool {
		get {
			stopped
		}
		set {
			guard stopped != newValue else {
				return
			}

			stopped = newValue

			if stopped {
				stopCurrentUtterance()
			}
		}
	}

	public func speak(_ item: SpeechItem) {
		guard !stopped else {
			return
		}
		if case let .notification(notification) = item {
			guard !notificationsMuted,
			      (notification.spokenText?.utf8.count ?? 0) <= Self.maximumNotificationBytes,
			      (notification.text?.utf8.count ?? 0) <= Self.maximumNotificationBytes else { return }
			if pendingItems.count(where: \.isNotification) >= Self.maximumPendingNotifications,
			   let oldest = pendingItems.firstIndex(where: \.isNotification)
			{
				pendingItems.remove(at: oldest)
			}
		}

		pendingItems.append(item)

		speakNextItem()
	}

	public func speak(text: String) {
		speak(.text(text))
	}

	public func clearQueue() {
		pendingItems.removeAll()
	}

	public func setNotificationsMuted(_ muted: Bool) {
		notificationsMuted = muted
		guard muted else { return }
		pendingItems.removeAll(where: \.isNotification)
		if case let .speaking(item) = engineState, item.isNotification {
			stopCurrentUtterance()
		}
	}

	public func clearQueue(for client: IRCClient) {
		let clientIdentifier = client.uniqueIdentifier

		pendingItems.removeAll { $0.belongs(to: clientIdentifier) }
	}

	/// Skips whatever is being said. An engine that has already gone quiet
	/// without reporting it is not left holding the queue up.
	public func stopSpeakingAndMoveForward() {
		if stopCurrentUtterance() == false {
			/* Nothing was cancelled, so no cancel callback is coming to move
			 the queue on. Move it on from here instead. */
			speakNextItem()
		}
	}

	/// Cuts the current utterance short, if there is one to cut. Returns
	/// whether the engine was asked to stop, which is what the cancel callback
	/// that moves the queue on answers.
	@discardableResult
	private func stopCurrentUtterance() -> Bool {
		guard engine.isSpeaking, engine.stopSpeakingImmediately() else {
			/* Either nothing was speaking or the engine had nothing left to
			 stop, and in neither case is a cancel callback coming. */
			engineState = .idle
			return false
		}

		engineState = .stopping
		return true
	}

	public var pendingItemCount: UInt {
		UInt(pendingItems.count)
	}

	public func speechSynthesizerEngineDidCompleteUtterance() {
		engineState = .idle
		speakNextItem()
	}

	private func speakNextItem() {
		while !stopped, canStartAnUtterance, !pendingItems.isEmpty {
			let nextItem = pendingItems.removeFirst()

			guard let text = nextItem.spokenText else {
				continue
			}

			engineState = .speaking(nextItem)
			engine.speakText(text)

			return
		}
	}

	private var canStartAnUtterance: Bool {
		guard engine.isSpeaking == false else {
			return false
		}

		switch engineState {
		case .idle:
			return true
		case .speaking:
			/* The engine went quiet without saying so. Whatever it was
			 speaking is over, so the queue moves on rather than stalls. */
			return true
		case .stopping:
			return false
		}
	}
}
