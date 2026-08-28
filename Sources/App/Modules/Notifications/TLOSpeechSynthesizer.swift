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

@objc(TLOSpeechSynthesizer)
public final nonisolated class SpeechSynthesizer: NSObject, SpeechSynthesizerEngineDelegate {
	private let lock = NSRecursiveLock()
	private let engine: SpeechSynthesizerEngine
	private var pendingItems: [Any] = []
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
			withLock { stopped }
		}
		set {
			withLock {
				guard stopped != newValue else {
					return
				}

				stopped = newValue

				if stopped, engine.isSpeaking {
					engine.stopSpeakingImmediately()
				}
			}
		}
	}

	@objc public func speak(_ object: Any) {
		let queued = withLock { () -> Bool in
			guard !stopped else {
				return false
			}

			pendingItems.append(object)

			return true
		}

		guard queued else {
			return
		}

		speakNextItem()
	}

	@objc public func clearQueue() {
		withLock {
			pendingItems.removeAll()
		}
	}

	@objc(clearQueueForClient:)
	public func clearQueue(for client: IRCClient) {
		withLock {
			pendingItems.removeAll { item in
				guard let notification = item as? SpokenNotification else {
					return false
				}

				return notification.client === client
			}
		}
	}

	@objc public func stopSpeakingAndMoveForward() {
		withLock {
			guard engine.isSpeaking else {
				return
			}

			engine.stopSpeakingImmediately()
		}
	}

	@objc public var pendingItemCount: UInt {
		withLock { UInt(pendingItems.count) }
	}

	@objc public func speechSynthesizerEngineDidCompleteUtterance() {
		speakNextItem()
	}

	/** Formatting a notification blocks on the main queue, so it must run with the lock
	 released: otherwise a main-thread caller of any locked method deadlocks. */
	private func speakNextItem() {
		while true {
			let nextItem: Any? = withLock {
				guard !stopped, !engine.isSpeaking, !pendingItems.isEmpty else {
					return nil
				}

				return pendingItems.removeFirst()
			}

			guard let nextItem else {
				return
			}

			let text: String? = if let notification = nextItem as? SpokenNotification {
				notification.spokenText
			} else {
				nextItem as? String
			}

			guard let text else {
				continue
			}

			withLock {
				guard !stopped, !engine.isSpeaking else {
					return
				}

				engine.speakText(text)
			}

			return
		}
	}

	@discardableResult
	private func withLock<Result>(_ operation: () -> Result) -> Result {
		lock.lock()
		defer { lock.unlock() }

		return operation()
	}
}
