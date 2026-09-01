/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/* The app and its static menu graph are created in code. Keeping these as
 top-level values gives the weak delegate/menu seams application lifetime. */
let application = Application.shared
let applicationController = ApplicationController()
let menuController = TXMenuController()
applicationController.menuController = menuController
application.delegate = applicationController

application.run()
