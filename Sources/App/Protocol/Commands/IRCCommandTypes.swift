/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

import Foundation

public enum IRCLocalCommand: UInt, Sendable {
	case adchat = 5001
	case ame = 5002
	case amsg = 5003
	case aquote = 5095
	case araw = 5096
	case autojoin = 5101
	case away = 5004
	case back = 5105
	case ban = 5005
	case cap = 5006
	case caps = 5007
	case chathistory = 5120
	case chatops = 5009
	case clear = 5010
	case clearall = 5011
	case close = 5012
	case conn = 5013
	case ctcp = 5014
	case ctcpreply = 5015
	case cycle = 5016
	case dcc = 5017
	case debug = 5018
	case defaults = 5092
	case dehalfop = 5019
	case deop = 5020
	case devoice = 5021
	case echo = 5022
	case gline = 5023
	case globops = 5024
	case goto = 5099
	case gzline = 5025
	case halfop = 5026
	case hop = 5027
	case ignore = 5029
	case invite = 5030
	case ison = 5100
	case j = 5031
	case join = 5032
	case joinRandom = 5109
	case kb = 5083
	case kick = 5033
	case kickban = 5034
	case kill = 5035
	case lagcheck = 5084
	case leave = 5036
	case list = 5037
	case locops = 5039
	/// `/m`, the shorthand for `/mode`.
	case modeShortcut = 5040
	case me = 5041
	case mode = 5042
	case monitor = 5106
	case msg = 5043
	case mute = 5044
	case mylag = 5045
	case myversion = 5046
	case nachat = 5047
	case names = 5094
	case nick = 5048
	case notice = 5050
	case notifybubble = 5112
	case notifysound = 5113
	case notifyspeak = 5114
	case omsg = 5051
	case onotice = 5052
	case op = 5053
	case part = 5054
	case pass = 5055
	case query = 5056
	case quiet = 5107
	case quit = 5057
	case quote = 5058
	case raw = 5059
	case recv = 5087
	case rejoin = 5060
	case remove = 5061
	case server = 5062
	case setcolor = 5103
	case setname = 5130
	case setqueryname = 5117
	case shun = 5063
	case silence = 5119
	case sme = 5064
	case smsg = 5065
	case sslcontext = 5066
	/// `/t`, the shorthand for `/topic`.
	case topicShortcut = 5067
	case tage = 5093
	case tempshun = 5068
	case timer = 5069
	case topic = 5070
	case ume = 5089
	case umode = 5071
	case umsg = 5088
	case unban = 5072
	case unignore = 5073
	case unmute = 5075
	case unotice = 5090
	case unquiet = 5108
	case voice = 5076
	case wallops = 5077
	case watch = 5097
	case weights = 5118
	case who = 5079
	case whois = 5080
	case whowas = 5081
	case zline = 5082
}

public enum IRCRemoteCommand: UInt, Sendable {
	case account = 1070
	case adchat = 1003
	case authenticate = 1005
	case away = 1050
	case batch = 1054
	case cap = 1004
	case certinfo = 1055
	case chatops = 1006
	case chghost = 1057
	case error = 1016
	case fail = 1059
	case gline = 1047
	case globops = 1017
	case gzline = 1048
	case invite = 1018
	case ison = 1019
	case join = 1020
	case kick = 1021
	case kill = 1022
	case list = 1023
	case markread = 1062
	case locops = 1024
	case mode = 1026
	case monitor = 1056
	case nachat = 1027
	case names = 1028
	case nick = 1029
	case note = 1061
	case notice = 1030
	case part = 1031
	case pass = 1032
	case ping = 1033
	case pong = 1034
	case privmsg = 1035
	case privmsgAction = 1002
	case quit = 1036
	case setname = 1071
	case shun = 1045
	case tagmsg = 1058
	case tempshun = 1046
	case time = 1012
	case topic = 1039
	case user = 1037
	case wallops = 1038
	case warn = 1060
	case watch = 1053
	case who = 1040
	case whois = 1042
	case whowas = 1041
	case zline = 1049
}
