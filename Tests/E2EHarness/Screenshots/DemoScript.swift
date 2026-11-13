// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/* The fictional conversation the website screenshots show. Every network,
 channel, nickname and line here is made up; nothing comes from a real server
 or a real person. */

struct DemoLine {
	let identifier: String
	let sender: String
	let text: String
	let minutesAgo: Int
	var replyTo: String?
	var isAction = false
}

struct DemoReaction {
	let sender: String
	let emoji: String
	let target: String
	let minutesAgo: Int
}

struct DemoChannel {
	let name: String
	let topic: String
	let members: [String]
	let lines: [DemoLine]
	let reactions: [DemoReaction]
	/// The first line that is said only once the reader has seen the ones
	/// before it and looked away. `nil` when every line arrives with the join.
	var unseenFrom: String?

	private var unseenStart: Int {
		unseenFrom.flatMap { identifier in lines.firstIndex { $0.identifier == identifier } } ?? lines.count
	}

	/// What the channel says as it is joined.
	var seenLines: [DemoLine] {
		Array(lines[..<unseenStart])
	}

	/// What it says after the reader has looked away: the lines the unread
	/// boundary is drawn above.
	var unseenLines: [DemoLine] {
		Array(lines[unseenStart...])
	}
}

struct DemoNetwork {
	let name: String
	/// The one-word name the server announces as `NETWORK`.
	let token: String
	let nickname: String
	let channels: [DemoChannel]
	/// Lines said to the user directly once registration ends.
	let directLines: [DemoLine]
	/// What the server says after the welcome.
	var messageOfTheDay: [String] = []
}

enum DemoScript {
	static let nickname = "casey"
	static let realName = "Casey Example"
	/// The soju account the two bouncer networks hang under.
	static let bouncerAccountName = "Demo Bouncer"
	/// Who offers the file in the secure transfer scene, and the file.
	static let transferSender = "marlow"
	static let transferFilename = "demo-slides.pdf"
	/// What the history search scene looks for, and the least number of
	/// scripted lines that hold it.
	static let searchQuery = "slides"
	static let searchMatches = 9
	/// How the last line a server console shows before the message of the
	/// day ends: the server's `005`.
	static let endOfConnectionLines = "are supported by this server"
	/// The address `/register` names in the inline question scene.
	static let email = "casey@example.com"
	/// The People window's two entries: one ignored, one tracked.
	static let ignoredHostmask = "*!*@ads.example.net"
	static let trackedNickname = "marlow"

	static let example = DemoNetwork(
		name: "Example Network",
		token: "Example",
		nickname: nickname,
		channels: [swift, macdev, design],
		directLines: [
			DemoLine(
				identifier: "d1", sender: "marlow", text: "Hey Casey, are you joining the demo tonight?", minutesAgo: 12
			),
			DemoLine(
				identifier: "d2", sender: "marlow", text: "I will share the slides here before we start.", minutesAgo: 11
			),
		],
		messageOfTheDay: [
			"Welcome to Example Network, a small community for people who build software.",
			"",
			"House rules",
			"  1. Be kind. Assume good intent and help newcomers.",
			"  2. Stay on topic in each channel.",
			"  3. No advertising and no unsolicited private messages.",
			"  4. Keep pasted code short and link to longer snippets.",
			"  5. Staff decisions are final, and staff are happy to explain them.",
			"",
			"Popular channels",
			"  #swift     Swift language talk",
			"  #macdev    Building apps for the Mac",
			"  #design    Interface design, typography and craft",
			"  #help      Questions about the network itself",
			"",
			"Connecting",
			"  TLS on port 6697 is the only way in. Certificates renew every month.",
			"  Bouncers are welcome. Please keep to five connections for each account.",
			"",
			"Accounts",
			"  Register to keep your nickname and your channel access:",
			"  /register * you@example.com",
			"  Sign in with SASL once the account is verified.",
			"",
			"Staff are in #help most of the day. Enjoy your stay!",
		]
	)

	static let swift = DemoChannel(
		name: "#swift",
		topic: "Swift language talk. Be kind, be curious. https://example.com/swift-guidelines",
		members: ["@jordan", "@riley", "+sam", "kai", "marlow", "noor", nickname],
		lines: [
			DemoLine(identifier: "p1", sender: "noor", text: "Good morning! Coffee first, then code.", minutesAgo: 96),
			DemoLine(
				identifier: "p2", sender: "kai",
				text: "Did anyone watch the talk on structured concurrency yesterday?", minutesAgo: 92
			),
			DemoLine(
				identifier: "p3", sender: "riley",
				text: "kai: Yes! The part about task groups finally made cancellation click for me.",
				minutesAgo: 90, replyTo: "p2"
			),
			DemoLine(identifier: "p3b", sender: "kai", text: "The slides are up if anyone missed it.", minutesAgo: 88),
			DemoLine(
				identifier: "p4", sender: "sam",
				text: "I am rewriting our networking layer around async sequences this week.", minutesAgo: 85
			),
			DemoLine(
				identifier: "p5", sender: "jordan",
				text: "sam: Nice. Do you keep a single actor for the connection state?", minutesAgo: 80, replyTo: "p4"
			),
			DemoLine(
				identifier: "p6", sender: "sam",
				text: "jordan: One actor per connection, and plain value types for everything that crosses it.",
				minutesAgo: 78, replyTo: "p5"
			),
			DemoLine(
				identifier: "p7", sender: "noor",
				text: "That matches what worked for us. Fewer locks, fewer surprises.", minutesAgo: 70
			),
			DemoLine(identifier: "p8", sender: "marlow", text: "Bookmarking this whole conversation.", minutesAgo: 60),
			DemoLine(
				identifier: "s1", sender: "jordan",
				text: "Morning all! Has anyone tried typed throws in a real project yet?", minutesAgo: 44
			),
			DemoLine(
				identifier: "s2", sender: "riley",
				text: "Yes, I replaced a few error enums with it. The call sites got much clearer.", minutesAgo: 41
			),
			DemoLine(
				identifier: "s3", sender: "sam",
				text: "jordan: Same here. Migrating was painless once the package dropped its old language mode.",
				minutesAgo: 38, replyTo: "s1"
			),
			DemoLine(
				identifier: "s4", sender: "marlow",
				text: "casey: your write-up on actor isolation helped me untangle a Sendable warning, thank you!",
				minutesAgo: 31
			),
			DemoLine(
				identifier: "s5", sender: nickname,
				text: "marlow: Glad it helped! Keeping the mutable state in one actor was the whole trick.",
				minutesAgo: 29, replyTo: "s4"
			),
			DemoLine(
				identifier: "s6", sender: "kai", text: "waves a copy of the new concurrency cheat sheet",
				minutesAgo: 24, isAction: true
			),
			DemoLine(
				identifier: "s7", sender: "jordan",
				text: "Notes from last week's meetup: https://example.com/swift-meetup-notes", minutesAgo: 17
			),
			DemoLine(
				identifier: "s8", sender: "noor", text: "Thanks for posting these, jordan. The slides were great.",
				minutesAgo: 9
			),
			DemoLine(
				identifier: "s9", sender: "riley", text: "Has anyone benchmarked the new string processing APIs?", minutesAgo: 6
			),
			DemoLine(
				identifier: "s10", sender: "jordan",
				text: "riley: Not yet, but I saw promising numbers for large inputs.", minutesAgo: 4, replyTo: "s9"
			),
			DemoLine(
				identifier: "s11", sender: "sam", text: "I will share a small benchmark project this afternoon.", minutesAgo: 2
			),
		],
		reactions: [
			DemoReaction(sender: "riley", emoji: "👍", target: "s4", minutesAgo: 30),
			DemoReaction(sender: "jordan", emoji: "❤️", target: "s4", minutesAgo: 30),
			DemoReaction(sender: "sam", emoji: "🎉", target: "s7", minutesAgo: 16),
			DemoReaction(sender: "kai", emoji: "👍", target: "s7", minutesAgo: 15),
		],
		// Everything after the reader's own last message.
		unseenFrom: "s6"
	)

	static let macdev = DemoChannel(
		name: "#macdev",
		topic: "Building apps for the Mac. Share tips, ask questions.",
		members: ["@devon", "+avery", "quinn", "riley", nickname],
		lines: [
			DemoLine(
				identifier: "m1", sender: "devon",
				text: "Anyone have a good pattern for restoring window state with SwiftUI scenes?", minutesAgo: 58
			),
			DemoLine(
				identifier: "m2", sender: "avery",
				text: "I keep the selection in the model and restore it on launch. Works every time.",
				minutesAgo: 52, replyTo: "m1"
			),
			DemoLine(
				identifier: "m3", sender: "quinn", text: "Menu commands feel so much better once focus is predictable.",
				minutesAgo: 20
			),
			DemoLine(
				identifier: "m4", sender: "devon",
				text: "The slides from the window restoration session are worth a second look.", minutesAgo: 18
			),
		],
		reactions: [],
		// Said while the reader is here, after #swift's unseen lines: seeing
		// it is how the scene knows those have arrived.
		unseenFrom: "m4"
	)

	static let design = DemoChannel(
		name: "#design",
		topic: "Interface design, typography and craft.",
		members: ["@noor", "+sam", "avery", "kai", nickname],
		lines: [
			DemoLine(
				identifier: "g1", sender: "noor",
				text: "Reminder: the system materials look best when you let them do the work.", minutesAgo: 70
			),
			DemoLine(
				identifier: "g2", sender: "kai",
				text: "Agreed. Fewer custom backgrounds, more space and good type.", minutesAgo: 66
			),
			DemoLine(
				identifier: "g3", sender: "avery", text: "noor: Could you share the slides from your typography talk?",
				minutesAgo: 50
			),
			DemoLine(identifier: "g4", sender: "noor", text: "avery: Of course. The slides are in the topic now.", minutesAgo: 47),
		],
		reactions: []
	)

	// Networks a bouncer account owns.

	static let workshop = DemoNetwork(
		name: "Workshop Chat",
		token: "Workshop",
		nickname: nickname,
		channels: [
			DemoChannel(
				name: "#swiftui",
				topic: "SwiftUI layouts, state and animation.",
				members: ["@riley", "+devon", "jordan", nickname],
				lines: [
					DemoLine(
						identifier: "w1", sender: "riley", text: "The new toolbar spacing is a nice touch.", minutesAgo: 35
					),
					DemoLine(
						identifier: "w2", sender: "devon", text: "Agreed, and sidebars just work now.", minutesAgo: 33
					),
					DemoLine(
						identifier: "w3", sender: "jordan", text: "Has anyone tried the new glass effects in a custom toolbar?",
						minutesAgo: 27
					),
					DemoLine(
						identifier: "w4", sender: "riley",
						text: "jordan: Yes, they look great as long as you keep the content simple.", minutesAgo: 25,
						replyTo: "w3"
					),
					DemoLine(
						identifier: "w5", sender: "devon", text: "casey, did you see the new layout guide?", minutesAgo: 14
					),
					DemoLine(
						identifier: "w6", sender: "devon", text: "https://example.com/layout-guide has the details.",
						minutesAgo: 13
					),
					DemoLine(
						identifier: "w7", sender: "riley", text: "The slides from the layout session are linked there too.",
						minutesAgo: 10
					),
				],
				reactions: []
			),
			DemoChannel(
				name: "#accessibility",
				topic: "Make it work for everyone.",
				members: ["@avery", "noor", nickname],
				lines: [
					DemoLine(
						identifier: "a1", sender: "avery", text: "Keyboard navigation first, then everything else.",
						minutesAgo: 80
					),
				],
				reactions: []
			),
		],
		directLines: []
	)

	static let openSource = DemoNetwork(
		name: "Open Source Hub",
		token: "OpenSource",
		nickname: nickname,
		channels: [
			DemoChannel(
				name: "#contributors",
				topic: "Welcome, new contributors!",
				members: ["@sam", "+kai", "quinn", nickname],
				lines: [
					DemoLine(
						identifier: "o1", sender: "sam", text: "Good first issues are labeled in the tracker.",
						minutesAgo: 90
					),
					DemoLine(
						identifier: "o2", sender: "quinn", text: "The slides from the onboarding call are in the wiki.",
						minutesAgo: 75
					),
				],
				reactions: []
			),
			DemoChannel(
				name: "#releases",
				topic: "Release announcements.",
				members: ["@kai", nickname],
				lines: [
					DemoLine(
						identifier: "r1", sender: "kai", text: "Version 2.4 is out. Release notes and the launch slides are on the site.",
						minutesAgo: 120
					),
				],
				reactions: []
			),
		],
		directLines: []
	)

	static let bouncerNetworks = [("1", workshop), ("2", openSource)]
}
