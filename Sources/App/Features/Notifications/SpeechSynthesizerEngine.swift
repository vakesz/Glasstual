/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AVFoundation
import Foundation

@MainActor
public protocol SpeechSynthesizerEngineDelegate: AnyObject {
	func speechSynthesizerEngineDidCompleteUtterance()
}

@MainActor
public protocol SpeechSynthesizerEngine: AnyObject {
	var delegate: SpeechSynthesizerEngineDelegate? { get set }
	var isSpeaking: Bool { get }

	func speakText(_ text: String)
	/// Cuts the current utterance short. Reports whether there was one to cut,
	/// which is whether a cancel callback is going to follow.
	func stopSpeakingImmediately() -> Bool
}

/** `AVSpeechSynthesizer` is main-thread affine, so the engine is too: that is
 what replaces the recursive lock the translation wrapped every call in. */
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

	public var isSpeaking: Bool {
		speechSynthesizer.isSpeaking
	}

	public func speakText(_ text: String) {
		let utterance = AVSpeechUtterance(string: text)
		utterance.rate = AVSpeechUtteranceDefaultSpeechRate

		speechSynthesizer.speak(utterance)
	}

	public func stopSpeakingImmediately() -> Bool {
		speechSynthesizer.stopSpeaking(at: .immediate)
	}

	public nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, // nonisolated: pure
	                                          didFinish _: AVSpeechUtterance)
	{
		notifyCompletion()
	}

	public nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, // nonisolated: pure
	                                          didCancel _: AVSpeechUtterance)
	{
		notifyCompletion()
	}

	private nonisolated func notifyCompletion() { // nonisolated: pure
		Task { @MainActor [weak self] in
			self?.delegate?.speechSynthesizerEngineDidCompleteUtterance()
		}
	}
}
