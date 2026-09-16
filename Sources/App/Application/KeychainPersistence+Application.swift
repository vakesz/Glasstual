/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

extension KeychainPersistence {
	/// Compose the process-wide writer with the application's error presenter.
	static let shared = KeychainPersistence(reportFailure: { error, retry in
		KeychainAlerts.showFailure(error, retry: retry)
	})
}
