import CocoaExtensions
@testable import Glasstual
import Testing

/** *********************************************************************
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
@Suite("Mode info")
struct ModeInfoTests {
	@Test("A mode built from a symbol alone is unset and carries no parameter")
	func convenienceInitializers() {
		let unset = ModeInfo(modeSymbol: "n")
		let set = ModeInfo(modeSymbol: "t", modeIsSet: true)

		#expect(unset.modeSymbol == "n")
		#expect(unset.modeIsSet == false)
		#expect(unset.modeParameter == nil)
		#expect(set.modeSymbol == "t")
		#expect(set.modeIsSet)
	}

	/// `GLTTestClient` and its support info are main-actor isolated; the rest
	/// of this suite works on plain values.
	@MainActor
	@Test("A member mode change needs both a prefix mode and a parameter")
	func memberModeRequiresAParameterAndPrefixMode() {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")

		let memberMode = ModeInfo(modeSymbol: "o", modeIsSet: true, modeParameter: "nick")
		let missingParameter = ModeInfo(modeSymbol: "o", modeIsSet: true)
		let channelMode = ModeInfo(modeSymbol: "n", modeIsSet: true, modeParameter: "nick")

		#expect(memberMode.isModeForChangingMemberMode(on: client))
		#expect(missingParameter.isModeForChangingMemberMode(on: client) == false)
		#expect(channelMode.isModeForChangingMemberMode(on: client) == false)
	}
}
