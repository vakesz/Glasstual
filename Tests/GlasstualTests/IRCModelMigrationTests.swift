import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelConfig.h"
// #import "IRCConnection.h"
// #import "IRCConnectionConfig.h"
// #import "IRCConnectionPrivate.h"
// #import "IRCHighlightLogEntryPrivate.h"
// #import "IRCHighlightMatchCondition.h"
// #import "IRCServerPrivate.h"
// #import "IRCUserPersistentStorePrivate.h"
// #import "IRCUserRelationsPrivate.h"
// #import "TVCLogLinePrivate.h"
// #pragma mark - Connection
// #pragma mark - Channel config
// #pragma mark - Highlight match condition
// #pragma mark - Server
// #pragma mark - Highlight log entry
// #pragma mark - Persistent store
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class IRCModelMigrationTests: XCTestCase {
    @objc
    func testConnectionInitialStateAndConfigIsolation() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        var sourceConfig: UnsafeMutablePointer<IRCConnectionConfigMutable>! = IRCConnectionConfigMutable()

        sourceConfig.serverAddress = "irc.example.test"

        let connection: UnsafeMutablePointer<IRCConnection>! = IRCConnection(config: sourceConfig, onClient: client)

        sourceConfig.serverAddress = "changed.example.test"

        XCTAssertEqual(connection.client, client)

        XCTAssertEqualObjects(connection.config.serverAddress, "irc.example.test")

        XCTAssertGreaterThan(connection.uniqueIdentifier.length, 0)

        XCTAssertFalse(connection.isConnecting)
        XCTAssertFalse(connection.isConnected)
        XCTAssertFalse(connection.isDisconnecting)
        XCTAssertFalse(connection.isSecured)
        XCTAssertFalse(connection.isSending)
        XCTAssertFalse(connection.EOFReceived)
    }
    @objc
    func testConnectionResetClearsTransientState() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let connection: UnsafeMutablePointer<IRCConnection>! = IRCConnection(config: IRCConnectionConfig(), onClient: client)

        connection.resetState()

        XCTAssertFalse(connection.isConnecting)
        XCTAssertFalse(connection.isConnected)
        XCTAssertFalse(connection.isConnectedWithClientSideCertificate)
        XCTAssertFalse(connection.isDisconnecting)
        XCTAssertFalse(connection.isSecured)
        XCTAssertFalse(connection.isSending)
        XCTAssertFalse(connection.EOFReceived)

        XCTAssertNil(connection.connectedAddress)
    }
    @objc
    func testChannelConfigDefaultsAndLegacyKeys() {
        let defaults: UnsafeMutablePointer<IRCChannelConfig>! = IRCChannelConfig.seedWithName("#general")

        XCTAssertTrue(defaults.autoJoin)
        XCTAssertTrue(defaults.pushNotifications)
        XCTAssertTrue(defaults.showTreeBadgeCount)

        XCTAssertEqual(defaults.type, IRCChannelTypeChannel)

        XCTAssertEqualObjects(defaults.channelName, "#general")

        XCTAssertGreaterThan(defaults.uniqueIdentifier.length, 0)

        let legacy: UnsafeMutablePointer<IRCChannelConfig>! = IRCChannelConfig(dictionary: ["channelName": "#legacy", "joinOnConnect": false, "ignoreJPQActivity": true, "enableNotifications": false, "enableTreeBadgeCountDrawing": false])

        XCTAssertFalse(legacy.autoJoin)

        XCTAssertTrue(legacy.ignoreGeneralEventMessages)

        XCTAssertFalse(legacy.pushNotifications)
        XCTAssertFalse(legacy.showTreeBadgeCount)
    }
    @objc
    func testChannelConfigMutableAndUniqueCopiesPreserveValues() {
        var mutable: UnsafeMutablePointer<IRCChannelConfigMutable>! = IRCChannelConfigMutable()

        mutable.channelName = "#swift"
        mutable.label = "Swift migration"
        mutable.defaultModes = "+nt"
        mutable.secretKey = "join-key"

        let copy: UnsafeMutablePointer<IRCChannelConfig>! = mutable.copy()
        let unique: UnsafeMutablePointer<IRCChannelConfigMutable>! = mutable.uniqueCopyMutable()

        XCTAssertEqualObjects(copy.channelName, "#swift")
        XCTAssertEqualObjects(copy.label, "Swift migration")
        XCTAssertEqualObjects(copy.defaultModes, "+nt")
        XCTAssertEqualObjects(copy.secretKey, "join-key")
        XCTAssertEqualObjects(copy.uniqueIdentifier, mutable.uniqueIdentifier)
        XCTAssertEqualObjects(unique.channelName, "#swift")
        XCTAssertEqualObjects(unique.secretKey, "join-key")

        XCTAssertNotEqualObjects(unique.uniqueIdentifier, mutable.uniqueIdentifier)
    }
    @objc
    func testChannelConfigNotificationOverridesUseThreeStateSemantics() {
        let config: UnsafeMutablePointer<IRCChannelConfigMutable>! = IRCChannelConfigMutable()
        let event: TXNotificationType = TXNotificationTypeHighlight

        XCTAssertEqual(config.notificationEnabledForEvent(event), NSControlStateValueMixed)

        config.setNotificationEnabled(NSControlStateValueOn, forEvent: event)

        XCTAssertEqual(config.notificationEnabledForEvent(event), NSControlStateValueOn)

        config.setNotificationEnabled(NSControlStateValueOff, forEvent: event)

        XCTAssertEqual(config.notificationEnabledForEvent(event), NSControlStateValueOff)

        config.setNotificationEnabled(NSControlStateValueMixed, forEvent: event)

        XCTAssertEqual(config.notificationEnabledForEvent(event), NSControlStateValueMixed)
    }
    @objc
    func testHighlightMatchConditionRoundTripsDictionaryAndDefaults() {
        let condition: UnsafeMutablePointer<IRCHighlightMatchCondition>! = IRCHighlightMatchCondition(dictionary: ["matchKeyword": "alert", "matchChannelID": "chan-1", "matchIsExcluded": true])

        XCTAssertEqualObjects(condition.matchKeyword, "alert")
        XCTAssertEqualObjects(condition.matchChannelId, "chan-1")

        XCTAssertTrue(condition.matchIsExcluded)

        XCTAssertGreaterThan(condition.uniqueIdentifier.length, 0)

        let dictionary: NSDictionary! = condition.dictionaryValue

        XCTAssertEqualObjects(dictionary["matchKeyword"], "alert")
        XCTAssertEqualObjects(dictionary["matchChannelID"], "chan-1")
        XCTAssertEqualObjects(dictionary["matchIsExcluded"], true)
        XCTAssertEqualObjects(dictionary["uniqueIdentifier"], condition.uniqueIdentifier)
    }
    @objc
    func testHighlightMatchConditionMutableCopyAndUniqueCopy() {
        let original: UnsafeMutablePointer<IRCHighlightMatchCondition>! = IRCHighlightMatchCondition(dictionary: ["matchKeyword": "ping"])
        var mutableCopy: UnsafeMutablePointer<IRCHighlightMatchConditionMutable>! = original.mutableCopy()

        mutableCopy.matchKeyword = "pong"
        mutableCopy.matchIsExcluded = true

        XCTAssertEqualObjects(original.matchKeyword, "ping")

        XCTAssertFalse(original.matchIsExcluded)

        XCTAssertEqualObjects(mutableCopy.matchKeyword, "pong")

        XCTAssertTrue(mutableCopy.matchIsExcluded)

        let unique: UnsafeMutablePointer<IRCHighlightMatchCondition>! = original.uniqueCopy()

        XCTAssertEqualObjects(unique.matchKeyword, "ping")
        XCTAssertNotEqualObjects(unique.uniqueIdentifier, original.uniqueIdentifier)
    }
    @objc
    func testServerDefaultsAndDictionaryRoundTrip() {
        let server: UnsafeMutablePointer<IRCServer>! = IRCServer(dictionary: ["serverAddress": "irc.example.test", "serverPort": 6697, "prefersSecuredConnection": true])

        XCTAssertEqualObjects(server.serverAddress, "irc.example.test")

        XCTAssertEqual(server.serverPort, 6697)

        XCTAssertTrue(server.prefersSecuredConnection)

        XCTAssertGreaterThan(server.uniqueIdentifier.length, 0)

        let empty: UnsafeMutablePointer<IRCServer>! = IRCServer()

        XCTAssertEqual(empty.serverPort, 6667)
        XCTAssertEqualObjects(empty.serverAddress, "")
    }
    @objc
    func testServerMutablePasswordAndUniqueCopy() {
        var mutable: UnsafeMutablePointer<IRCServerMutable>! = IRCServerMutable()

        mutable.serverAddress = "chat.example.test"
        mutable.serverPort = 6667
        mutable.serverPassword = "s3cret"
        mutable.prefersSecuredConnection = false

        XCTAssertEqualObjects(mutable.serverPassword, "s3cret")

        let unique: UnsafeMutablePointer<IRCServer>! = mutable.uniqueCopy()

        XCTAssertEqualObjects(unique.serverAddress, "chat.example.test")
        XCTAssertNotEqualObjects(unique.uniqueIdentifier, mutable.uniqueIdentifier)
        XCTAssertEqualObjects(unique.serverPassword, "s3cret")
    }
    @objc
    func testHighlightLogEntryMutableStoresLineClientAndChannel() {
        var line: UnsafeMutablePointer<TVCLogLineMutable>! = TVCLogLineMutable()

        line.messageBody = "hello world"
        line.nickname = "alice"
        line.lineType = TVCLogLineTypePrivateMessage
        line.receivedAt = Date.dateWithTimeIntervalSince1970(1700000000)

        var entry: UnsafeMutablePointer<IRCHighlightLogEntryMutable>! = IRCHighlightLogEntryMutable()

        entry.lineLogged = line
        entry.clientId = "client-a"
        entry.channelId = "channel-b"

        XCTAssertEqualObjects(entry.clientId, "client-a")
        XCTAssertEqualObjects(entry.channelId, "channel-b")
        XCTAssertEqualObjects(entry.lineNumber, line.uniqueIdentifier)
        XCTAssertEqualObjects(entry.timeLogged, line.receivedAt)

        XCTAssertGreaterThan(entry.renderedMessage.length, 0)
        XCTAssertGreaterThan(entry.timeLoggedFormatted.length, 0)
    }
    @objc
    func testUserPersistentStoreHoldsRelationsAndTimerSlot() {
        var store: UnsafeMutablePointer<IRCUserPersistentStore>! = IRCUserPersistentStore()
        let relations: UnsafeMutablePointer<IRCUserRelations>! = IRCUserRelations()

        store.relations = relations
        store.presentAwayMessageFor301LastEvent = 12.5

        XCTAssertEqual(store.relations, relations)
        XCTAssertEqual(store.presentAwayMessageFor301LastEvent, 12.5)

        XCTAssertNil(store.removeUserTimer)
    }
}