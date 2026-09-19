// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// Numeric replies and errors sent by IRC servers.
///
/// The raw value is the three-digit number the server sends; the cases are in
/// that order.
enum ServerNumeric: UInt, CaseIterable, Sendable {
	case welcome = 1
	case yourhost = 2
	case created = 3
	case myinfo = 4
	case isupport = 5
	case redir = 10
	case umodeis = 221
	case statsconn = 250
	case lusersession = 251
	case luserhop = 252
	case luserunknown = 253
	case luserchannels = 254
	case luserme = 255
	case localusers = 265
	case globalusers = 266
	case silelist = 271
	case endofsilelist = 272
	case whoiscertfp = 276
	case away = 301
	case ison = 303
	case unaway = 305
	case nowaway = 306
	case whoisregnick = 307
	case whoishelpop = 310
	case whoisuser = 311
	case whoisserver = 312
	case whoisoperator = 313
	case whowasuser = 314
	case endofwho = 315
	case whoisidle = 317
	case endofwhois = 318
	case whoischannels = 319
	case whoisspecial = 320
	case liststart = 321
	case list = 322
	case listend = 323
	case channelmodeis = 324
	case channelUrl = 328
	case creationtime = 329
	case whoisaccount = 330
	case topic = 332
	case topicwhotime = 333
	case whoisbot = 335
	case whoisactually = 338
	case inviting = 341
	case invitelist = 346
	case endofinvitelist = 347
	case exceptlist = 348
	case endofexceptlist = 349
	case whoreply = 352
	case namereply = 353
	case whospcrpl = 354
	case endofnames = 366
	case banlist = 367
	case endofbanlist = 368
	case endofwhowas = 369
	case motd = 372
	case motdstart = 375
	case endofmotd = 376
	case whoishost = 378
	case whoismodes = 379
	case youreoper = 381
	case nosuchnick = 401
	case nosuchserver = 402
	case nosuchchannel = 403
	case cannotsendtochan = 404
	case toomanychannels = 405
	case unknowncommand = 421
	case nomotd = 422
	case erroneusnickname = 432
	case nicknameinuse = 433
	case bannickchange = 435
	case unavailresource = 437
	case nicktoofast = 438
	case cantchangenick = 447
	case forbiddenchannel = 448
	case nohiding = 459
	case needmoreparams = 461
	case linkchannel = 470
	case channelisfull = 471
	case inviteonlychan = 473
	case bannedfromchan = 474
	case badchannelkey = 475
	case badchanmask = 476
	case needreggednick = 477
	case badchanname = 479
	case throttle = 480
	case secureonlychan = 489
	case delayrejoin = 495
	case toomanyjoins = 500
	case toomanywatch = 512
	case disabled = 517
	case admonly = 519
	case operonly = 520
	case whosyntax = 522
	case wholimexceed = 523
	case operspverify = 524
	case reaway = 597
	case goneaway = 598
	case notaway = 599
	case logon = 600
	case logoff = 601
	case watchoff = 602
	case watchstat = 603
	case nowon = 604
	case nowoff = 605
	case watchlist = 606
	case endofwatchlist = 607
	case clearwatch = 608
	case channelsmsg = 651
	case whowasip = 652
	case whoissecure = 671
	case whoisrealip = 672
	case targumodeg = 716
	case targnotify = 717
	case umodegmsg = 718
	case quietlist = 728
	case endofquietlist = 729
	case mononline = 730
	case monoffline = 731
	case monlist = 732
	case endofmonlist = 733
	case monlistfull = 734
	case loggedin = 900
	case loggedout = 901
	case nicklocked = 902
	case saslsuccess = 903
	case saslfail = 904
	case sasltoolong = 905
	case saslaborted = 906
	case saslalready = 907
	case saslmechs = 908
	case badchannel = 926

	/// Which handler answers the numeric.
	///
	/// `receiveNumericReply` makes one routing decision from this and the
	/// handler it picks answers with a plain switch. `nil` means no handler
	/// claims the numeric, so it takes the generic reply path.
	var group: Group? {
		switch self {
		case .welcome, .yourhost, .created, .myinfo, .isupport, .redir, .umodeis, .statsconn,
		     .lusersession, .luserhop, .luserunknown, .luserchannels, .luserme, .localusers, .globalusers,
		     .silelist, .endofsilelist, .away, .unaway, .nowaway, .motd, .motdstart, .endofmotd, .nomotd:
			.connection
		case .whoisregnick, .whoishelpop, .whoisuser, .whoisserver, .whoisoperator, .whowasuser,
		     .whoisidle, .endofwhois, .whoischannels, .whoisspecial, .whoisaccount, .whoisbot,
		     .whoisactually, .endofwhowas, .whoishost, .whoismodes, .channelsmsg, .whoissecure, .whoisrealip:
			.whois
		case .ison, .liststart, .list, .listend, .channelmodeis, .creationtime, .topic, .topicwhotime,
		     .inviting, .invitelist, .endofinvitelist, .exceptlist, .endofexceptlist, .whoreply,
		     .namereply, .whospcrpl, .endofwho, .endofnames, .banlist, .endofbanlist,
		     .quietlist, .endofquietlist:
			.channel
		case .youreoper, .channelUrl, .reaway, .goneaway, .notaway, .logon, .logoff, .watchoff,
		     .watchstat, .nowon, .nowoff, .watchlist, .endofwatchlist,
		     .mononline, .monoffline, .monlist, .endofmonlist, .monlistfull, .targumodeg:
			.presence
		case .targnotify, .umodegmsg, .loggedin, .loggedout, .saslsuccess, .saslmechs,
		     .nicklocked, .saslfail, .sasltoolong, .saslaborted, .saslalready:
			.authentication
		default:
			nil
		}
	}

	/// The reply is printed whether or not a rule asked for it to be
	/// suppressed, because its handler reads state out of it either way.
	var requiresSpecialFiltering: Bool {
		switch self {
		case .umodeis, .channelmodeis, .topic, .topicwhotime: true
		default: false
		}
	}

	var isErrorReply: Bool {
		Self.isErrorReply(rawValue)
	}

	/// Numerics from 400 to 596 are errors by convention — 400 is
	/// `ERR_UNKNOWNERROR` — and RPL_NOMOTD sits inside that range without being
	/// one. The test takes a raw value because servers send error numerics this
	/// enum has no case for and those still have to reach the error path.
	static func isErrorReply(_ rawValue: UInt) -> Bool {
		rawValue >= 400 && rawValue < 597 && rawValue != ServerNumeric.nomotd.rawValue
	}

	/** What kind of failure an error numeric reports.

	 The inbound error path answers a whole kind the same way whichever numeric
	 carried it, and this is the one place that says which numerics make up a
	 kind. The kinds do not overlap. */
	var errorKind: ErrorKind? {
		switch self {
		case .nosuchserver, .nosuchchannel:
			.missingTarget
		case .nicknameinuse, .erroneusnickname:
			.nicknameCollision
		case .admonly, .badchanmask, .badchanname, .badchannel, .badchannelkey, .bannedfromchan,
		     .channelisfull, .delayrejoin, .forbiddenchannel, .inviteonlychan, .linkchannel,
		     .needreggednick, .nohiding, .operonly, .operspverify, .secureonlychan, .throttle,
		     .toomanychannels, .toomanyjoins:
			.joinFailure
		case .whosyntax, .wholimexceed:
			.whoFailure
		case .disabled, .unknowncommand, .needmoreparams:
			.commandFailure
		default:
			nil
		}
	}

	/// The handler a numeric belongs to.
	enum Group: Sendable {
		case connection
		case whois
		case channel
		case presence
		case authentication
	}

	/// The kind of failure an error numeric reports.
	enum ErrorKind: Sendable {
		case missingTarget
		case nicknameCollision
		case joinFailure
		case whoFailure
		case commandFailure
	}
}
