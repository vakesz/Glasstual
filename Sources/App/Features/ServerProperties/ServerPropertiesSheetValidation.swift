/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation

enum ServerPropertiesValidation {
	static func isNickname(_ value: String) -> Bool {
		(value as NSString).isHostmaskNickname
	}

	static func isUsername(_ value: String) -> Bool {
		(value as NSString).isHostmaskUsername
	}

	static func isInternetAddress(_ value: String) -> Bool {
		(value as NSString).isValidInternetAddress
	}

	static func isInternetPort(_ value: String) -> Bool {
		(value as NSString).isValidInternetPort
	}

	static func isSingleLine(_ value: String) -> Bool {
		value.rangeOfCharacter(from: .newlines) == nil
	}

	static let maximumCommentLength = 390

	static func isLeavingComment(_ value: String) -> Bool {
		isSingleLine(value) && value.count <= maximumCommentLength
	}

	static func areAlternateNicknamesValid(_ value: String) -> Bool {
		invalidAlternateNickname(in: value) == nil
	}

	static func invalidAlternateNickname(in value: String) -> String? {
		value.components(separatedBy: .whitespaces)
			.first { $0.isEmpty == false && isNickname($0) == false }
	}
}
