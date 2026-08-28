/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AVFoundation
import Foundation

@objc(TLOSpeechSynthesizerEngineDelegate)
public nonisolated protocol SpeechSynthesizerEngineDelegate: AnyObject {
	func speechSynthesizerEngineDidCompleteUtterance()
}

@objc(TLOSpeechSynthesizerEngine)
public nonisolated protocol SpeechSynthesizerEngine: AnyObject {
	var delegate: SpeechSynthesizerEngineDelegate? { get set }
	var isSpeaking: Bool { get }

	func speakText(_ text: String)
	func stopSpeakingImmediately()
}

@objc(TLOAVSpeechSynthesizerEngine)
public final nonisolated class AVSpeechSynthesizerEngine: NSObject, @unchecked Sendable, SpeechSynthesizerEngine,
	AVSpeechSynthesizerDelegate
{
	private let lock = NSRecursiveLock()
	private weak var delegateStorage: SpeechSynthesizerEngineDelegate?

	private let speechSynthesizer = AVSpeechSynthesizer()

	@objc public var delegate: SpeechSynthesizerEngineDelegate? {
		get { lock.withLock { delegateStorage } }
		set { lock.withLock { delegateStorage = newValue } }
	}

	override public init() {
		super.init()

		speechSynthesizer.delegate = self
	}

	deinit {
		speechSynthesizer.delegate = nil
	}

	@objc public var isSpeaking: Bool {
		lock.withLock { speechSynthesizer.isSpeaking }
	}

	@objc(speakText:)
	public func speakText(_ text: String) {
		lock.withLock {
			let utterance = AVSpeechUtterance(string: text)
			utterance.rate = AVSpeechUtteranceDefaultSpeechRate

			speechSynthesizer.speak(utterance)
		}
	}

	@objc public func stopSpeakingImmediately() {
		_ = lock.withLock {
			speechSynthesizer.stopSpeaking(at: .immediate)
		}
	}

	public func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
		notifyCompletionOnMainQueue()
	}

	public func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
		notifyCompletionOnMainQueue()
	}

	private func notifyCompletionOnMainQueue() {
		DispatchQueue.main.async { [weak self] in
			guard let self else {
				return
			}

			let delegate = lock.withLock { delegateStorage }
			delegate?.speechSynthesizerEngineDidCompleteUtterance()
		}
	}
}
