/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

#import "OELReachability.h"

NS_ASSUME_NONNULL_BEGIN

@interface OELReachability ()
/* Returns 0 none, 1 became reachable, 2 became unreachable. Updates both inout flags. */
+ (NSInteger)evaluatePathChange:(BOOL)reachable
			 currentlyReachable:(BOOL *)currentlyReachable
			receivedInitialPath:(BOOL *)receivedInitialPath;
@end

NS_ASSUME_NONNULL_END
