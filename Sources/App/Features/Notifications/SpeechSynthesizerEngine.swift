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

	/** Both callbacks are `@objc` protocol requirements, so they are nonisolated
	 whichever thread `AVSpeechSynthesizer` happens to call them on. Each is a
	 hop and nothing else; the completion itself belongs to the main actor,
	 where the engine and its delegate live. */
	public nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, // nonisolated: xpc-shim
	                                          didFinish _: AVSpeechUtterance)
	{
		Task { @MainActor [weak self] in self?.notifyCompletion() }
	}

	public nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, // nonisolated: xpc-shim
	                                          didCancel _: AVSpeechUtterance)
	{
		Task { @MainActor [weak self] in self?.notifyCompletion() }
	}

	private func notifyCompletion() {
		delegate?.speechSynthesizerEngineDidCompleteUtterance()
	}
}
