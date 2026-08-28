/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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
import InlineContentKit

@objc(ICMAssessedMedia)
final class AssessedMediaModule: InlineContentModule {
	/** Renders through the framework's own template into an escaped attribute,
	 and carries no adult content of its own. */
	override static var contentUntrusted: Bool {
		false
	}

	override static var contentNotSafeForWork: Bool {
		false
	}

	private var mediaAssessor: MediaAssessor?

	@objc(_assessMedia)
	private func assessMedia() {
		let assessor = MediaAssessor(url: payload.url, expectedType: .unknown) { [weak self] assessment, error in
			guard let self else { return }

			if
				let assessment,
				error == nil,
				InlineContentModule.isTypeDeferrable(assessment.type)
			{
				payload.urlToInline = assessment.url
				deferContent(as: assessment.type, performCheck: false)
			} else {
				cancel()
			}

			mediaAssessor = nil
		}

		mediaAssessor = assessor
		assessor.resume()
	}

	override static func action(for _: URL) -> Selector? {
		TextualPreferences.inlineMediaCheckEverything() ? #selector(assessMedia) : nil
	}

	override static var contentImageOrVideo: Bool {
		true
	}

	override static var contentIsFile: Bool {
		true
	}
}
