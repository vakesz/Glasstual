/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

/// Numeric replies and errors sent by IRC servers.
///
/// Raw values intentionally match the wire protocol catalog that this type replaces.
enum IRCNumeric: UInt, CaseIterable, Sendable {
	case welcome = 1
	case yourhost = 2
	case created = 3
	case myinfo = 4
	case isupport = 5
	case redir = 10
	case umodeis = 221
	case statsconn = 250
	case luserclient = 251
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
	case loggedin = 900
	case loggedout = 901
	case saslsuccess = 903
	case saslmechs = 908
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
	case monlistfull = 734
	case nicklocked = 902
	case saslfail = 904
	case sasltoolong = 905
	case saslaborted = 906
	case saslalready = 907
	case badchannel = 926

	var isErrorReply: Bool {
		rawValue > 400 && rawValue < 597 && self != .nomotd
	}
}
