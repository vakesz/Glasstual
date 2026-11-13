@testable import Glasstual
import Testing

/// The File Transfers toolbar shares a narrow window with its title and
/// direction filter. Stopping or starting the selected transfer stays in view;
/// the other commands overflow first.
@Suite("File transfer toolbar commands")
struct FileTransferActionTests {
	@Test("Start and Stop hold their place in the toolbar, ahead of the rest")
	func startAndStopHoldTheirPlace() {
		let kept = FileTransferAction.toolbarCommands.filter(\.keepsToolbarPlace)
		#expect(kept == [.start, .stop])
	}

	@Test("Every other toolbar command overflows before Start and Stop")
	func secondaryCommandsOverflowFirst() {
		let overflowing = FileTransferAction.toolbarCommands.filter { $0.keepsToolbarPlace == false }
		#expect(overflowing == [.downloadTo, .preview, .showCertificate])
	}
}
