import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "TLOSpokenNotificationPrivate.h"
// #import "TLOSpeechSynthesizerTestingPrivate.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class TLOSpeechSynthesizerEngineSpy: NSObject, TLOSpeechSynthesizerEngine {
    @objc weak var delegate: TLOSpeechSynthesizerEngineDelegate?
    @objc var speaking: Bool = false
    @objc var stopCount: UInt = 0
    @objc var spokenTexts: NSMutableArray

    @objc
    override init() {
        if self = super.init() {
            self.spokenTexts = NSMutableArray()
        }

        return self
    }

    @objc
    func speakText(_ text: String) {
        self.spokenTexts.add(text)
        self.speaking = true
    }
    @objc
    func stopSpeakingImmediately() {
        self.stopCount += 1
        self.speaking = false
    }
    @objc
    func completeCurrentUtterance() {
        self.speaking = false
        self.delegate?.speechSynthesizerEngineDidCompleteUtterance()
    }
}
@objc
class TLOSpeechSynthesizerTests: XCTestCase {
    @objc
    func testQueuedTextStartsInOrderAsUtterancesComplete() {
        let engine = TLOSpeechSynthesizerEngineSpy()
        let synthesizer: UnsafeMutablePointer<TLOSpeechSynthesizer>! = TLOSpeechSynthesizer(engine: engine)

        synthesizer.speak("first")
        synthesizer.speak("second")

        XCTAssertEqualObjects(engine.spokenTexts, ["first"])

        XCTAssertEqual(synthesizer.pendingItemCount, 1)

        engine.completeCurrentUtterance()

        XCTAssertEqualObjects(engine.spokenTexts, ["first", "second"])

        XCTAssertEqual(synthesizer.pendingItemCount, 0)
    }
    @objc
    func testStoppingRejectsNewItemsAndStopsCurrentUtterance() {
        let engine = TLOSpeechSynthesizerEngineSpy()
        var synthesizer: UnsafeMutablePointer<TLOSpeechSynthesizer>! = TLOSpeechSynthesizer(engine: engine)

        synthesizer.speak("active")
        synthesizer.isStopped = true
        synthesizer.speak("ignored")

        XCTAssertEqual(engine.stopCount, 1)

        XCTAssertEqualObjects(engine.spokenTexts, ["active"])

        XCTAssertEqual(synthesizer.pendingItemCount, 0)
    }
    @objc
    func testClearQueueLeavesCurrentUtteranceAlone() {
        let engine = TLOSpeechSynthesizerEngineSpy()
        let synthesizer: UnsafeMutablePointer<TLOSpeechSynthesizer>! = TLOSpeechSynthesizer(engine: engine)

        synthesizer.speak("active")
        synthesizer.speak("queued")
        synthesizer.clearQueue()

        XCTAssertTrue(engine.isSpeaking)

        XCTAssertEqual(synthesizer.pendingItemCount, 0)

        XCTAssertEqualObjects(engine.spokenTexts, ["active"])
    }
    @objc
    func testClearQueueForClientRemovesOnlyMatchingNotifications() {
        let engine = TLOSpeechSynthesizerEngineSpy()

        engine.speaking = true

        let synthesizer: UnsafeMutablePointer<TLOSpeechSynthesizer>! = TLOSpeechSynthesizer(engine: engine)
        let firstClient: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let secondClient: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let firstNotification: UnsafeMutablePointer<TLOSpokenNotification>! = TLOSpokenNotification(notification: TXNotificationTypeConnect, lineType: TVCLogLineTypeNotice, target: firstClient, nickname: "first", text: "one")
        let secondNotification: UnsafeMutablePointer<TLOSpokenNotification>! = TLOSpokenNotification(notification: TXNotificationTypeConnect, lineType: TVCLogLineTypeNotice, target: secondClient, nickname: "second", text: "two")

        synthesizer.speak(firstNotification)
        synthesizer.speak(secondNotification)
        synthesizer.speak("plain text")
        synthesizer.clearQueueForClient(firstClient)

        XCTAssertEqual(synthesizer.pendingItemCount, 2)

        engine.completeCurrentUtterance()

        XCTAssertEqual(synthesizer.pendingItemCount, 1)
    }
    @objc
    func testUnsupportedQueueItemDoesNotBlockFollowingText() {
        let engine = TLOSpeechSynthesizerEngineSpy()

        engine.speaking = true

        let synthesizer: UnsafeMutablePointer<TLOSpeechSynthesizer>! = TLOSpeechSynthesizer(engine: engine)

        synthesizer.speak(42)
        synthesizer.speak("valid")

        engine.completeCurrentUtterance()

        XCTAssertEqualObjects(engine.spokenTexts, ["valid"])

        XCTAssertEqual(synthesizer.pendingItemCount, 0)
    }
}