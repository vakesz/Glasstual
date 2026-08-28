/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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
@objc(TLOSpeechSynthesizer)
@MainActor
public final class SpeechSynthesizer: NSObject, SpeechSynthesizerEngineDelegate {
	private let engine: SpeechSynthesizerEngine
	private var pendingItems: [SpeechItem] = []
	private var stopped = false

	override public convenience init() {
		self.init(engine: AVSpeechSynthesizerEngine())
	}

	@objc(initWithEngine:)
	public init(engine: SpeechSynthesizerEngine) {
		self.engine = engine

		super.init()

		engine.delegate = self
	}

	@objc public var isStopped: Bool {
		get {
			stopped
		}
		set {
			guard stopped != newValue else {
				return
			}

			stopped = newValue

			if stopped, engine.isSpeaking {
				engine.stopSpeakingImmediately()
			}
		}
	}

	public func speak(_ item: SpeechItem) {
		guard !stopped else {
			return
		}

		pendingItems.append(item)

		speakNextItem()
	}

	@objc(speakText:)
	public func speak(text: String) {
		speak(.text(text))
	}

	@objc public func clearQueue() {
		pendingItems.removeAll()
	}

	@objc(clearQueueForClient:)
	public func clearQueue(for client: IRCClient) {
		let clientIdentifier = client.uniqueIdentifier

		pendingItems.removeAll { $0.belongs(to: clientIdentifier) }
	}

	@objc public func stopSpeakingAndMoveForward() {
		guard engine.isSpeaking else {
			return
		}

		engine.stopSpeakingImmediately()
	}

	@objc public var pendingItemCount: UInt {
		UInt(pendingItems.count)
	}

	public func speechSynthesizerEngineDidCompleteUtterance() {
		speakNextItem()
	}

	private func speakNextItem() {
		while !stopped, !engine.isSpeaking, !pendingItems.isEmpty {
			let nextItem = pendingItems.removeFirst()

			guard let text = nextItem.spokenText else {
				continue
			}

			engine.speakText(text)

			return
		}
	}
}
