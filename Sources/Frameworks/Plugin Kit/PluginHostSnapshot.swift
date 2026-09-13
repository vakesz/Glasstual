/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

public struct PluginApplicationSnapshot: Equatable, Sendable {
	public let timeIntervalSinceLaunch: TimeInterval
	public let timeIntervalSinceInstall: TimeInterval
	public let runCount: UInt
	public let birthday: TimeInterval

	public init(
		timeIntervalSinceLaunch: TimeInterval,
		timeIntervalSinceInstall: TimeInterval,
		runCount: UInt,
		birthday: TimeInterval
	) {
		self.timeIntervalSinceLaunch = timeIntervalSinceLaunch
		self.timeIntervalSinceInstall = timeIntervalSinceInstall
		self.runCount = runCount
		self.birthday = birthday
	}
}

public enum PluginThemeStorageLocation: UInt, Sendable {
	case unknown = 0
	case bundled = 1
	case custom = 2
}

public enum PluginThemeAppearance: UInt, Sendable {
	case system = 0
	case dark = 1
	case light = 2
}

public struct PluginThemeSnapshot: Equatable, Sendable {
	public let name: String
	public let storageLocation: PluginThemeStorageLocation
	public let resolvedAppearance: PluginThemeAppearance

	public init(
		name: String,
		storageLocation: PluginThemeStorageLocation,
		resolvedAppearance: PluginThemeAppearance
	) {
		self.name = name
		self.storageLocation = storageLocation
		self.resolvedAppearance = resolvedAppearance
	}
}
