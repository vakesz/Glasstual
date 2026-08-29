@testable import CoreMediaModules
import Foundation
import InlineContentKit
import Testing

/// A module that never declares how much its content can be trusted gets the
/// cautious answer, so forgetting to say costs a gated module rather than an
/// ungated injection point.
@Suite("Inline content module trust")
struct InlineContentModuleTrustTests {
	/// Declares nothing beyond what the protocol demands, so every gate answer
	/// it gives comes from the protocol's own defaults.
	private struct SilentModule: InlineContentModule {
		static func module(for _: URL) -> (any InlineContentModule)? {
			nil
		}

		func run(payload: InlineContentPayloadValues) async -> InlineContentOutcome {
			.finished(payload)
		}
	}

	@Test("A module that declares nothing is treated as untrusted and not safe for work")
	func protocolDefaultsAreCautious() {
		#expect(SilentModule.contentUntrusted)
		#expect(SilentModule.contentNotSafeForWork)
		#expect(SilentModule.contentImageOrVideo == false)
		#expect(SilentModule.contentIsFile == false)
		#expect(SilentModule.domains == nil)
	}

	@Test("The image and video modules declare themselves trusted")
	func mediaModulesAreTrusted() {
		#expect(InlineImageModule.contentUntrusted == false)
		#expect(InlineImageModule.contentNotSafeForWork == false)
		#expect(InlineVideoModule.contentUntrusted == false)
		#expect(InlineVideoModule.contentNotSafeForWork == false)
	}

	@Test("The modules that inject a remote endpoint's markup stay untrusted")
	func markupModulesStayUntrusted() {
		/* The tweet module renders Twitter's markup, not the framework's. */
		#expect(TweetModule.contentUntrusted)
		#expect(TweetModule.contentNotSafeForWork == false)
	}

	@Test("The adult-content module says so")
	func adultModuleDeclaresItself() {
		#expect(PornhubModule.contentNotSafeForWork)
	}
}
