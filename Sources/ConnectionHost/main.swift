// Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

let delegate = ConnectionHostListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
