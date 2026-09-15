/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/// The virtual key codes the window and the message field bind shortcuts to.
public enum KeyCode: UInt16, Sendable {
	/// `kVK_ANSI_A`. Zero is a real key code, not "no key".
	case keyA = 0x00
	case returnKey = 0x24
	case tab = 0x30
	case space = 0x31
	case backspace = 0x33
	case escape = 0x35
	case enter = 0x4C
	case home = 0x73
	case pageUp = 0x74
	case forwardDelete = 0x75
	case end = 0x77
	case pageDown = 0x79
	case leftArrow = 0x7B
	case rightArrow = 0x7C
	case downArrow = 0x7D
	case upArrow = 0x7E
}
