/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AVFoundation
import Foundation

@objc(TLOAVSpeechSynthesizerEngine)
public final class AVSpeechSynthesizerEngine: NSObject, TLOSpeechSynthesizerEngine, AVSpeechSynthesizerDelegate {
	@objc public weak var delegate: TLOSpeechSynthesizerEngineDelegate?

	private let speechSynthesizer = AVSpeechSynthesizer()

	override public init() {
		super.init()

		speechSynthesizer.delegate = self
	}

	deinit {
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
		speechSynthesizer.stopSpeaking(at: .immediate)
	}

	public func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
		notifyCompletionOnMainQueue()
	}

	public func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
		notifyCompletionOnMainQueue()
	}

	private func notifyCompletionOnMainQueue() {
		DispatchQueue.main.async { [weak self] in
			self?.delegate?.speechSynthesizerEngineDidCompleteUtterance()
		}
	}
}
