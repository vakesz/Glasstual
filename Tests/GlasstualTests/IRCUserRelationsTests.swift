import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCChannelPrivate.h"
// #import "IRCChannelMemberListPrivate.h"
// #import "IRCChannelUserPrivate.h"
// #import "IRCTreeItemPrivate.h"
// #import "IRCUser.h"
// #import "IRCUserRelationsPrivate.h"
/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */
@objc
class IRCUserRelationsTests: XCTestCase {
    @objc var client: UnsafeMutablePointer<GLTTestClient>
    @objc var relations: UnsafeMutablePointer<IRCUserRelations>

    @objc
    override func setUp() {
        super.setUp()
        self.client = GLTTestClient.testClient()
        self.relations = IRCUserRelations()
    }
    @objc
    func channelNamed(_ name: String) -> UnsafeMutablePointer<IRCChannel> {
        var channel: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": name])

        channel.associatedClient = self.client

        return channel
    }
    @objc
    func memberNamed(_ nickname: String) -> UnsafeMutablePointer<IRCChannelUser> {
        let user: UnsafeMutablePointer<IRCUser>! = IRCUser(nickname: nickname, onClient: self.client)

        return IRCChannelUser(user: user)
    }
    @objc
    func testAssociatingAndDisassociatingChannelMember() {
        let channel = self.channelNamed("#chat")
        let member = self.memberNamed("alice")

        self.relations.associateUser(member, withChannel: channel)

        XCTAssertEqual(self.relations.numberOfRelations, 1)

        XCTAssertEqualObjects(self.relations.relatedChannels, [channel])
        XCTAssertEqualObjects(self.relations.relatedUsers, [member])

        XCTAssertEqual(self.relations.userAssociatedWithChannel(channel), member)

        self.relations.disassociateUserWithChannel(channel)

        XCTAssertEqual(self.relations.numberOfRelations, 0)

        XCTAssertNil(self.relations.userAssociatedWithChannel(channel))
    }
    @objc
    func testReplacingRelationForSameChannel() {
        let channel = self.channelNamed("#chat")
        let first = self.memberNamed("alice")
        let second = self.memberNamed("bob")

        self.relations.associateUser(first, withChannel: channel)
        self.relations.associateUser(second, withChannel: channel)

        XCTAssertEqual(self.relations.numberOfRelations, 1)
        XCTAssertEqual(self.relations.userAssociatedWithChannel(channel), second)
    }
    @objc
    func testEnumerationUsesSnapshotAndHonorsStop() {
        self.relations.associateUser(self.memberNamed("alice"), withChannel: self.channelNamed("#one"))
        self.relations.associateUser(self.memberNamed("bob"), withChannel: self.channelNamed("#two"))

        var visitedCount: UInt = 0

        self.relations.enumerateRelations { (channel: UnsafeMutablePointer<IRCChannel>!, member: UnsafeMutablePointer<IRCChannelUser>!, stop: UnsafeMutablePointer<Bool>!) -> Void in
            visitedCount += 1
            *stop = true
        }
        XCTAssertEqual(visitedCount, 1)
    }
    @objc
    func testPrivateMessageChannelsAreNotStored() {
        var privateMessage: UnsafeMutablePointer<IRCChannel>! = IRCChannel(configDictionary: ["channelName": "alice", "channelType": IRCChannelTypePrivateMessage])

        privateMessage.associatedClient = self.client

        let member = self.memberNamed("alice")

        self.relations.associateUser(member, withChannel: privateMessage)
        XCTAssertEqual(self.relations.numberOfRelations, 0)
        XCTAssertNil(self.relations.userAssociatedWithChannel(privateMessage))
    }
    @objc
    func testChannelUserCopiesPreserveIdentityModesAndConversationWeights() {
        let user: UnsafeMutablePointer<IRCUser>! = IRCUser(nickname: "alice", onClient: self.client)
        var member: UnsafeMutablePointer<IRCChannelUserMutable>! = IRCChannelUserMutable(user: user)

        member.modes = "ov"
        member.incomingConversation()
        member.outgoingConversation()

        let copy: UnsafeMutablePointer<IRCChannelUser>! = member.copy()
        let uniqueMutableCopy: UnsafeMutablePointer<IRCChannelUserMutable>! = member.uniqueCopyMutable()

        XCTAssertEqual(copy.user, user)

        XCTAssertEqualObjects(copy.modes, "ov")

        XCTAssertEqual(copy.ranks, IRCUserRankNormalOperator | IRCUserRankVoiced)
        XCTAssertEqual(copy.incomingWeight, 100.0)
        XCTAssertEqual(copy.outgoingWeight, 20.0)
        XCTAssertEqual(copy.creationTime, member.creationTime)
        XCTAssertEqual(uniqueMutableCopy.user, user)

        XCTAssertEqualObjects(uniqueMutableCopy.modes, "ov")

        XCTAssertEqual(uniqueMutableCopy.incomingWeight, 100.0)
        XCTAssertEqual(uniqueMutableCopy.outgoingWeight, 20.0)
    }
    @objc
    func testChannelMemberListAddsSortsAndRemovesMembers() {
        let channel = self.channelNamed("#chat")
        let memberList: UnsafeMutablePointer<IRCChannelMemberList>! = IRCChannelMemberList(channel: channel)
        let bob = self.memberNamed("bob")
        let alice = self.memberNamed("alice")

        memberList.addMember(bob)
        memberList.addMember(alice)

        XCTAssertEqual(memberList.numberOfMembers, 2)

        XCTAssertEqualObjects(memberList.memberList.valueForKeyPath("user.nickname"), ["alice", "bob"])

        memberList.removeMember(alice)

        XCTAssertEqual(memberList.numberOfMembers, 1)

        XCTAssertEqualObjects(memberList.memberList, [bob])

        XCTAssertNil(alice.user.userAssociatedWithChannel(channel))
    }
    @objc
    func testChannelMemberListDuplicateCheckReplacesExistingRelation() {
        let channel = self.channelNamed("#chat")
        let memberList: UnsafeMutablePointer<IRCChannelMemberList>! = IRCChannelMemberList(channel: channel)
        let user: UnsafeMutablePointer<IRCUser>! = IRCUser(nickname: "alice", onClient: self.client)
        let original: UnsafeMutablePointer<IRCChannelUser>! = IRCChannelUser(user: user)
        let replacement: UnsafeMutablePointer<IRCChannelUser>! = IRCChannelUser(user: user)

        memberList.addMember(original)
        memberList.addMember(replacement, checkForDuplicates: true)

        XCTAssertEqual(memberList.numberOfMembers, 1)
        XCTAssertEqual(memberList.memberList.firstObject, replacement)
        XCTAssertEqual(user.userAssociatedWithChannel(channel), replacement)
    }
}