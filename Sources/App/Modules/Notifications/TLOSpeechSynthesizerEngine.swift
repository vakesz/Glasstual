/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AVFoundation
import Foundation

@objc(TLOSpeechSynthesizerEngineDelegate)
@MainActor
public protocol SpeechSynthesizerEngineDelegate: AnyObject {
	func speechSynthesizerEngineDidCompleteUtterance()
}

@objc(TLOSpeechSynthesizerEngine)
@MainActor
public protocol SpeechSynthesizerEngine: AnyObject {
	var delegate: SpeechSynthesizerEngineDelegate? { get set }
	var isSpeaking: Bool { get }

	func speakText(_ text: String)
	func stopSpeakingImmediately()
}

/** `AVSpeechSynthesizer` is main-thread affine, so the engine is too: that is
 what replaces the recursive lock the translation wrapped every call in. */
@objc(TLOAVSpeechSynthesizerEngine)
@MainActor
public final class AVSpeechSynthesizerEngine: NSObject, SpeechSynthesizerEngine, AVSpeechSynthesizerDelegate {
	public weak var delegate: SpeechSynthesizerEngineDelegate?

	private let speechSynthesizer = AVSpeechSynthesizer()

	override public init() {
		super.init()

		speechSynthesizer.delegate = self
	}

	isolated deinit {
		speechSynthesizer.delegate = nil
	}

	@objc public var isSpeaking: Bool {
		speechSynthesizer.isSpeaking
	}

	@objc(speakText:)
	public func speakText(_ text: String) {
		let utterance = AVSpeechUtterance(string: text)
		utterance.rate = AVSpeechUtteranceDefaultSpeechRate

		speechSynthesizer.speak(utterance)
	}

	@objc public func stopSpeakingImmediately() {
		_ = speechSynthesizer.stopSpeaking(at: .immediate)
	}

	public nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
		notifyCompletion()
	}

	public nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
		notifyCompletion()
	}

	private nonisolated func notifyCompletion() {
		Task { @MainActor [weak self] in
			self?.delegate?.speechSynthesizerEngineDidCompleteUtterance()
		}
	}
}
